// Package openfoodfacts implements product.Source on top of the Open Food
// Facts read API (https://world.openfoodfacts.org). The data is crowd-sourced
// and licensed under the ODbL, so every product is reported with its source.
package openfoodfacts

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"example.com/calsnap/server/internal/app/product"
)

// maxResponseBytes bounds the response body; a product with the requested
// fields is a few kilobytes.
const maxResponseBytes = 1 << 20

const (
	maxNameRunes  = 100
	maxBrandRunes = 60
	kJPerKcal     = 4.184

	// Plausibility bounds per 100 g. The data is entered by volunteers, so a
	// value outside these (kJ typed as kcal, a misplaced decimal point) means
	// the product cannot be trusted.
	maxKcal         = 900
	maxMacro        = 100
	maxMacroSum     = 105 // rounding on labels allows a little above 100
	maxServingGrams = 2000
)

// Config configures the client.
type Config struct {
	BaseURL string // e.g. https://world.openfoodfacts.org
	// UserAgent identifies the application; Open Food Facts asks for it.
	UserAgent string
}

// Client reads products. It is safe for concurrent use.
type Client struct {
	cfg    Config
	client *http.Client
}

var _ product.Source = (*Client)(nil)

// New creates a Client that sends requests with client, which must have a
// timeout configured.
func New(cfg Config, client *http.Client) *Client {
	cfg.BaseURL = strings.TrimRight(cfg.BaseURL, "/")
	return &Client{cfg: cfg, client: client}
}

// Lookup implements product.Source.
//
// NOTE: the barcode is part of the request URL; it is never included in
// returned errors, so it cannot reach the logs through them.
func (c *Client) Lookup(ctx context.Context, barcode, locale string) (product.Product, error) {
	fields := "product_name,product_name_en,product_name_ru,brands,serving_quantity,nutriments"
	endpoint := c.cfg.BaseURL + "/api/v2/product/" + url.PathEscape(barcode) + ".json?fields=" + url.QueryEscape(fields)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, http.NoBody)
	if err != nil {
		return product.Product{}, fmt.Errorf("build product request: %w", err)
	}
	req.Header.Set("User-Agent", c.cfg.UserAgent)
	req.Header.Set("Accept", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		var uerr *url.Error
		if errors.As(err, &uerr) {
			err = uerr.Err // drop the URL, it contains the barcode
		}
		return product.Product{}, fmt.Errorf("%w: product request failed: %w", product.ErrUnavailable, err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes+1))
	if err != nil {
		return product.Product{}, fmt.Errorf("%w: reading product response: %w", product.ErrUnavailable, err)
	}
	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusNotFound:
		// v2 answers 404 (with a JSON body) for an unknown code.
		return product.Product{}, product.ErrNotFound
	default:
		// 429, 5xx and anything else unexpected: the caller may try again later.
		return product.Product{}, fmt.Errorf("%w: product source returned HTTP %d", product.ErrUnavailable, resp.StatusCode)
	}
	if len(data) > maxResponseBytes {
		return product.Product{}, fmt.Errorf("%w: response exceeds %d bytes", product.ErrUnavailable, maxResponseBytes)
	}
	return parse(data, barcode, locale)
}

// flex reads a number that the source sometimes sends as a JSON string. A
// value that is neither stays invalid, so it is treated as absent, never as 0.
type flex struct {
	v  float64
	ok bool
}

func (f *flex) UnmarshalJSON(b []byte) error {
	if string(b) == "null" {
		return nil // the source sends null for unknown values
	}
	var n float64
	if err := json.Unmarshal(b, &n); err == nil {
		f.v, f.ok = n, !math.IsNaN(n) && !math.IsInf(n, 0)
		return nil
	}
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return nil
	}
	n, err := strconv.ParseFloat(strings.TrimSpace(strings.ReplaceAll(s, ",", ".")), 64)
	if err != nil || math.IsNaN(n) || math.IsInf(n, 0) {
		return nil
	}
	f.v, f.ok = n, true
	return nil
}

type response struct {
	Status  int `json:"status"`
	Product *struct {
		Name            string          `json:"product_name"`
		NameEN          string          `json:"product_name_en"`
		NameRU          string          `json:"product_name_ru"`
		Brands          string          `json:"brands"`
		ServingQuantity flex            `json:"serving_quantity"`
		Nutriments      map[string]flex `json:"nutriments"`
	} `json:"product"`
}

func parse(data []byte, barcode, locale string) (product.Product, error) {
	var r response
	if err := json.Unmarshal(data, &r); err != nil {
		return product.Product{}, fmt.Errorf("%w: product envelope: %w", product.ErrUnavailable, err)
	}
	if r.Status != 1 || r.Product == nil {
		return product.Product{}, product.ErrNotFound
	}
	p := r.Product

	n, ok := nutrition(p.Nutriments)
	if !ok {
		// Known, but without numbers that can be trusted: as good as unknown.
		return product.Product{}, product.ErrNotFound
	}

	localized, other := p.NameEN, p.NameRU
	if locale == product.LocaleRU {
		localized, other = p.NameRU, p.NameEN
	}
	brand := cleanText(firstBrand(p.Brands), maxBrandRunes)
	name := ""
	for _, candidate := range []string{localized, p.Name, other} {
		if name = cleanText(candidate, maxNameRunes); name != "" {
			break
		}
	}
	if name == "" {
		name = brand
	}
	if name == "" {
		name = "Packaged food"
	}

	serving := 0.0
	if q := p.ServingQuantity; q.ok && q.v > 0 && q.v <= maxServingGrams {
		serving = q.v
	}
	return product.Product{
		Barcode:      barcode,
		Name:         name,
		Brand:        brand,
		ServingSizeG: serving,
		Nutrition:    n,
	}, nil
}

// nutrition reads kcal and macros per 100 g. Energy falls back to kJ.
func nutrition(m map[string]flex) (product.Nutrition, bool) {
	get := func(key string) (float64, bool) {
		v := m[key]
		return v.v, v.ok
	}
	kcal, ok := get("energy-kcal_100g")
	if !ok {
		kj, hasKJ := get("energy_100g")
		if !hasKJ {
			return product.Nutrition{}, false
		}
		kcal = kj / kJPerKcal
	}
	protein, _ := get("proteins_100g")
	fat, _ := get("fat_100g")
	carbs, _ := get("carbohydrates_100g")

	n := product.Nutrition{Kcal: round1(kcal), Protein: round1(protein), Fat: round1(fat), Carbs: round1(carbs)}
	switch {
	case n.Kcal < 0 || n.Kcal > maxKcal,
		n.Protein < 0 || n.Protein > maxMacro,
		n.Fat < 0 || n.Fat > maxMacro,
		n.Carbs < 0 || n.Carbs > maxMacro,
		n.Protein+n.Fat+n.Carbs > maxMacroSum:
		return product.Nutrition{}, false
	}
	return n, true
}

func round1(v float64) float64 { return math.Round(v*10) / 10 }

func firstBrand(brands string) string {
	first, _, _ := strings.Cut(brands, ",")
	return first
}

// cleanText drops control characters, collapses white space and cuts the text
// to maxRunes. Product data is untrusted input.
func cleanText(s string, maxRunes int) string {
	s = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, s)
	s = strings.Join(strings.Fields(s), " ")
	if utf8.RuneCountInString(s) > maxRunes {
		s = string([]rune(s)[:maxRunes])
	}
	return strings.TrimSpace(s)
}
