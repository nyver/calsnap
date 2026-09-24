package openfoodfacts_test

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/product"
	"example.com/calsnap/server/internal/productsource/openfoodfacts"
)

const barcode = "4006381333931"

func newClient(t *testing.T, h http.HandlerFunc) *openfoodfacts.Client {
	t.Helper()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return openfoodfacts.New(openfoodfacts.Config{BaseURL: srv.URL + "/", UserAgent: "CalSnap-test/1.0"},
		&http.Client{Timeout: 3 * time.Second})
}

func respond(status int, body string) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body)
	}
}

const danone = `{"status":1,"code":"4006381333931","product":{
  "product_name":"Yaourt nature","product_name_en":"Plain yogurt","product_name_ru":"Йогурт натуральный",
  "brands":"Danone,Activia","serving_quantity":"125",
  "nutriments":{"energy-kcal_100g":61,"energy_100g":255,"proteins_100g":3.5,"fat_100g":"2.1","carbohydrates_100g":4.7}}}`

func TestLookupMapsAProduct(t *testing.T) {
	t.Parallel()

	var path, query, agent string
	c := newClient(t, func(w http.ResponseWriter, r *http.Request) {
		path, query, agent = r.URL.Path, r.URL.RawQuery, r.Header.Get("User-Agent")
		respond(http.StatusOK, danone)(w, r)
	})
	got, err := c.Lookup(context.Background(), barcode, "en")
	if err != nil {
		t.Fatal(err)
	}
	want := product.Product{
		Barcode: barcode, Name: "Plain yogurt", Brand: "Danone", ServingSizeG: 125,
		Nutrition: product.Nutrition{Kcal: 61, Protein: 3.5, Fat: 2.1, Carbs: 4.7},
	}
	if got != want {
		t.Errorf("got %+v\nwant %+v", got, want)
	}
	if path != "/api/v2/product/"+barcode+".json" || !strings.Contains(query, "fields=") {
		t.Errorf("request = %s?%s", path, query)
	}
	if agent != "CalSnap-test/1.0" {
		t.Errorf("User-Agent = %q", agent)
	}
}

func TestLookupPicksTheNameForTheLocale(t *testing.T) {
	t.Parallel()

	c := newClient(t, respond(http.StatusOK, danone))
	ru, err := c.Lookup(context.Background(), barcode, "ru")
	if err != nil || ru.Name != "Йогурт натуральный" {
		t.Errorf("ru = %+v, %v", ru, err)
	}

	onlyGeneric := `{"status":1,"product":{"product_name":"Yaourt","nutriments":{"energy-kcal_100g":50}}}`
	c = newClient(t, respond(http.StatusOK, onlyGeneric))
	got, _ := c.Lookup(context.Background(), barcode, "ru")
	if got.Name != "Yaourt" {
		t.Errorf("fallback name = %q", got.Name)
	}

	noName := `{"status":1,"product":{"brands":"Danone, Other","nutriments":{"energy-kcal_100g":50}}}`
	c = newClient(t, respond(http.StatusOK, noName))
	got, _ = c.Lookup(context.Background(), barcode, "en")
	if got.Name != "Danone" || got.Brand != "Danone" {
		t.Errorf("brand as name = %+v", got)
	}

	nothing := `{"status":1,"product":{"nutriments":{"energy-kcal_100g":50}}}`
	c = newClient(t, respond(http.StatusOK, nothing))
	got, _ = c.Lookup(context.Background(), barcode, "en")
	if got.Name == "" {
		t.Error("a nameless product still needs a name")
	}
}

func TestLookupConvertsKilojoulesWhenKcalIsMissing(t *testing.T) {
	t.Parallel()

	body := `{"status":1,"product":{"product_name":"Bar","nutriments":{"energy_100g":1500,"proteins_100g":6,"fat_100g":20,"carbohydrates_100g":60}}}`
	got, err := newClient(t, respond(http.StatusOK, body)).Lookup(context.Background(), barcode, "en")
	if err != nil {
		t.Fatal(err)
	}
	if got.Nutrition.Kcal != 358.5 {
		t.Errorf("kcal = %v, want 358.5", got.Nutrition.Kcal)
	}
}

func TestLookupDeclinesUnusableProducts(t *testing.T) {
	t.Parallel()

	tests := map[string]string{
		"unknown to the source":   `{"status":0,"status_verbose":"product not found"}`,
		"no product object":       `{"status":1}`,
		"no energy at all":        `{"status":1,"product":{"product_name":"X","nutriments":{"proteins_100g":3}}}`,
		"no nutriments":           `{"status":1,"product":{"product_name":"X"}}`,
		"kJ typed as kcal":        `{"status":1,"product":{"product_name":"X","nutriments":{"energy-kcal_100g":2100}}}`,
		"negative energy":         `{"status":1,"product":{"product_name":"X","nutriments":{"energy-kcal_100g":-5}}}`,
		"protein above 100 g":     `{"status":1,"product":{"product_name":"X","nutriments":{"energy-kcal_100g":300,"proteins_100g":140}}}`,
		"macros add up too high":  `{"status":1,"product":{"product_name":"X","nutriments":{"energy-kcal_100g":400,"proteins_100g":50,"fat_100g":40,"carbohydrates_100g":40}}}`,
		"null energy":             `{"status":1,"product":{"product_name":"X","nutriments":{"energy-kcal_100g":null,"energy_100g":null}}}`,
		"non-numeric energy text": `{"status":1,"product":{"product_name":"X","nutriments":{"energy-kcal_100g":"lots"}}}`,
	}
	for name, body := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			_, err := newClient(t, respond(http.StatusOK, body)).Lookup(context.Background(), barcode, "en")
			if !errors.Is(err, product.ErrNotFound) {
				t.Errorf("error = %v, want ErrNotFound", err)
			}
		})
	}
}

func TestLookupHandlesNullsLikeTheRealSource(t *testing.T) {
	t.Parallel()

	// A null serving and a null macro are unknown, not zero: the serving stays
	// unknown and the product is still usable through its energy value.
	body := `{"code":"` + barcode + `","status":1,"status_verbose":"product found","product":{"product_name":"Spread",` +
		`"product_name_ru":null,"serving_quantity":null,"brands":"Nutella, Ferrero",` +
		`"nutriments":{"energy-kcal_100g":539,"energy_100g":2252,"proteins_100g":6.3,"fat_100g":30.9,"carbohydrates_100g":57.5,"fiber_100g":null}}}`
	got, err := newClient(t, respond(http.StatusOK, body)).Lookup(context.Background(), barcode, "ru")
	if err != nil {
		t.Fatal(err)
	}
	want := product.Product{
		Barcode: barcode, Name: "Spread", Brand: "Nutella",
		Nutrition: product.Nutrition{Kcal: 539, Protein: 6.3, Fat: 30.9, Carbs: 57.5},
	}
	if got != want {
		t.Errorf("got %+v, want %+v", got, want)
	}
}

func TestLookupSanitizesUntrustedText(t *testing.T) {
	t.Parallel()

	long := strings.Repeat("Ж", 300)
	body := `{"status":1,"product":{"product_name":"  Milk\u0000\n\t  drink  ","brands":"` + long + `","nutriments":{"energy-kcal_100g":50}}}`
	got, err := newClient(t, respond(http.StatusOK, body)).Lookup(context.Background(), barcode, "en")
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "Milk drink" {
		t.Errorf("name = %q", got.Name)
	}
	if n := len([]rune(got.Brand)); n != 60 {
		t.Errorf("brand length = %d runes, want 60", n)
	}
}

func TestLookupIgnoresAbsurdServingSizes(t *testing.T) {
	t.Parallel()

	for _, serving := range []string{`0`, `-5`, `50000`, `"n/a"`} {
		body := `{"status":1,"product":{"product_name":"X","serving_quantity":` + serving + `,"nutriments":{"energy-kcal_100g":50}}}`
		got, err := newClient(t, respond(http.StatusOK, body)).Lookup(context.Background(), barcode, "en")
		if err != nil || got.ServingSizeG != 0 {
			t.Errorf("serving %s: %+v, %v", serving, got, err)
		}
	}
}

func TestLookupErrorClassification(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		handler http.HandlerFunc
		want    error
	}{
		{"404 is an unknown product", respond(http.StatusNotFound, `{"status":0}`), product.ErrNotFound},
		{"429", respond(http.StatusTooManyRequests, `slow down`), product.ErrUnavailable},
		{"500", respond(http.StatusInternalServerError, `oops`), product.ErrUnavailable},
		{"503", respond(http.StatusServiceUnavailable, ``), product.ErrUnavailable},
		{"403", respond(http.StatusForbidden, `blocked`), product.ErrUnavailable},
		{"broken JSON", respond(http.StatusOK, `{"status":`), product.ErrUnavailable},
		{"HTML instead of JSON", respond(http.StatusOK, `<html>maintenance</html>`), product.ErrUnavailable},
		{"oversized body", respond(http.StatusOK, `{"status":1,"pad":"`+strings.Repeat("A", 2<<20)+`"}`), product.ErrUnavailable},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := newClient(t, tt.handler).Lookup(context.Background(), barcode, "en")
			if !errors.Is(err, tt.want) {
				t.Errorf("error = %v, want %v", err, tt.want)
			}
			if err != nil && strings.Contains(err.Error(), barcode) {
				t.Errorf("the error leaks the barcode: %v", err)
			}
		})
	}
}

func TestLookupNetworkFailuresAndCancellation(t *testing.T) {
	t.Parallel()

	srv := httptest.NewServer(http.NotFoundHandler())
	url := srv.URL
	srv.Close() // nothing listens any more
	c := openfoodfacts.New(openfoodfacts.Config{BaseURL: url, UserAgent: "t"}, &http.Client{Timeout: time.Second})
	_, err := c.Lookup(context.Background(), barcode, "en")
	if !errors.Is(err, product.ErrUnavailable) {
		t.Errorf("error = %v", err)
	}
	if err != nil && strings.Contains(err.Error(), barcode) {
		t.Errorf("the error leaks the barcode: %v", err)
	}

	slow := newClient(t, func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-r.Context().Done():
		case <-time.After(2 * time.Second):
		}
		respond(http.StatusOK, danone)(w, r)
	})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := slow.Lookup(ctx, barcode, "en"); !errors.Is(err, context.Canceled) {
		t.Errorf("cancelled lookup error = %v", err)
	}
}
