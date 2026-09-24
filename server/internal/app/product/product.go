// Package product implements the packaged-product lookup use case: it
// validates a barcode, asks a product data source for the nutrition facts of
// the product and caches the answer in memory.
//
// The Source interface is defined on the consumer side so that Open Food Facts
// can be replaced or complemented without touching the transport.
package product

import (
	"context"
	"errors"
	"strings"
)

// Locales supported for product names.
const (
	LocaleEN = "en"
	LocaleRU = "ru"
)

var (
	// ErrInvalidBarcode marks input that is not a valid GTIN.
	ErrInvalidBarcode = errors.New("invalid barcode")
	// ErrNotFound means the source knows no usable product for the barcode:
	// unknown, or known without trustworthy nutrition data.
	ErrNotFound = errors.New("product not found")
	// ErrUnavailable marks a transient source failure (network, timeout, HTTP
	// 429/5xx).
	ErrUnavailable = errors.New("product source unavailable")
)

// Nutrition holds values per 100 g (or 100 ml) of the product.
type Nutrition struct {
	Kcal    float64
	Protein float64
	Fat     float64
	Carbs   float64
}

// Product is a packaged food.
type Product struct {
	// Barcode is the normalized code, see NormalizeBarcode.
	Barcode string
	Name    string
	// Brand may be empty.
	Brand string
	// ServingSizeG is the declared serving in grams, 0 when unknown.
	ServingSizeG float64
	Nutrition    Nutrition
}

// Source looks a product up by its normalized barcode. Implementations return
// errors wrapping ErrNotFound or ErrUnavailable.
type Source interface {
	Lookup(ctx context.Context, barcode, locale string) (Product, error)
}

// NormalizeBarcode validates a GTIN and returns its canonical form. It accepts
// GTIN-8, GTIN-12 (UPC-A), GTIN-13 (EAN-13) and GTIN-14 with a correct check
// digit; a UPC-A code gets a leading zero and becomes an EAN-13.
func NormalizeBarcode(raw string) (string, error) {
	code := strings.TrimSpace(raw)
	switch len(code) {
	case 8, 12, 13, 14:
	default:
		return "", ErrInvalidBarcode
	}
	for _, r := range code {
		if r < '0' || r > '9' {
			return "", ErrInvalidBarcode
		}
	}
	if !validCheckDigit(code) {
		return "", ErrInvalidBarcode
	}
	if len(code) == 12 {
		code = "0" + code
	}
	return code, nil
}

// validCheckDigit verifies the GS1 check digit: from the right, the digits
// before the check digit are weighted 3, 1, 3, 1, ...
func validCheckDigit(code string) bool {
	sum := 0
	weight := 3
	for i := len(code) - 2; i >= 0; i-- {
		sum += int(code[i]-'0') * weight
		weight = 4 - weight
	}
	return (10-sum%10)%10 == int(code[len(code)-1]-'0')
}
