package gemini_test

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/testutil"
	"example.com/calsnap/server/internal/vision/gemini"
)

func TestReadLabelRequestAndResult(t *testing.T) {
	t.Parallel()

	var raw string
	valid := string(testutil.Fixture(t, "ai-label-per100g.json"))
	p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		raw = string(b)
		respond(http.StatusOK, envelope(valid, "STOP"))(w, r)
	})
	ext, err := p.ReadLabel(context.Background(), testImage, analysis.RequestContext{Locale: "ru"})
	if err != nil {
		t.Fatalf("ReadLabel: %v", err)
	}
	if !ext.Found || ext.Basis != "per_100g" || ext.EnergyKcal == nil || *ext.EnergyKcal != 220 ||
		ext.Usage.InputTokens != 1300 || ext.Usage.OutputTokens != 210 {
		t.Errorf("extraction = %+v", ext)
	}
	for _, want := range []string{
		base64.StdEncoding.EncodeToString(testImage.Data), "nutrition facts table", "responseSchema", "Russian", "per_100g",
	} {
		if !strings.Contains(raw, want) {
			t.Errorf("request does not contain %q", want)
		}
	}
	if strings.Contains(raw, "estimatedWeightG") || strings.Contains(raw, "Identify each distinct food") {
		t.Error("a label request must not carry the meal instructions or schema")
	}
	if strings.Contains(raw, testKey) {
		t.Error("API key must not appear in the request body")
	}
}

func TestReadLabelRejectsInvalidAnswers(t *testing.T) {
	t.Parallel()

	for _, fixture := range []string{
		"ai-label-invalid-basis.json", "ai-label-invalid-negative.json", "ai-label-invalid-unknown-field.json",
	} {
		t.Run(fixture, func(t *testing.T) {
			t.Parallel()
			body := string(testutil.Fixture(t, fixture))
			p := newProvider(t, respond(http.StatusOK, envelope(body, "STOP")))
			if _, err := p.ReadLabel(context.Background(), testImage, analysis.RequestContext{}); !errors.Is(err, analysis.ErrInvalidResponse) {
				t.Errorf("err = %v, want ErrInvalidResponse", err)
			}
		})
	}
}

func TestReadLabelNotFoundIsAValidAnswer(t *testing.T) {
	t.Parallel()

	p := newProvider(t, respond(http.StatusOK, envelope(string(testutil.Fixture(t, "ai-label-not-found.json")), "STOP")))
	ext, err := p.ReadLabel(context.Background(), testImage, analysis.RequestContext{})
	if err != nil || ext.Found {
		t.Errorf("ext = %+v, err = %v", ext, err)
	}
}

func TestReadLabelErrorClassification(t *testing.T) {
	t.Parallel()

	tests := map[string]struct {
		status int
		want   error
	}{
		"429": {http.StatusTooManyRequests, analysis.ErrUnavailable},
		"500": {http.StatusInternalServerError, analysis.ErrUnavailable},
		"400": {http.StatusBadRequest, analysis.ErrRejected},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			p := newProvider(t, respond(tt.status, `{"error":"secret detail"}`))
			_, err := p.ReadLabel(context.Background(), testImage, analysis.RequestContext{})
			if !errors.Is(err, tt.want) {
				t.Errorf("err = %v, want %v", err, tt.want)
			}
			if err != nil && strings.Contains(err.Error(), "secret detail") {
				t.Error("provider error bodies must not leak into errors")
			}
		})
	}
}

// TestLabelResponseSchemaMatchesProtocol keeps the Gemini label schema in sync
// with the published JSON Schema: same properties and required lists.
func TestLabelResponseSchemaMatchesProtocol(t *testing.T) {
	t.Parallel()

	var proto map[string]any
	if err := json.Unmarshal(testutil.ReadProtocol(t, "ai/nutrition-label-result.schema.json"), &proto); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(gemini.LabelResponseSchema())
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}
	if names(proto["required"]) != names(got["required"]) {
		t.Errorf("required %s != %s", names(proto["required"]), names(got["required"]))
	}
	pp, _ := proto["properties"].(map[string]any)
	gp, _ := got["properties"].(map[string]any)
	if keys(pp) != keys(gp) {
		t.Errorf("properties %s != %s", keys(pp), keys(gp))
	}
}
