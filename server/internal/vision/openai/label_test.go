package openai_test

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
	"example.com/calsnap/server/internal/vision/openai"
)

func TestReadLabelRequestAndResult(t *testing.T) {
	t.Parallel()

	var raw string
	valid := string(testutil.Fixture(t, "ai-label-per100g.json"))
	p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		raw = string(b)
		respond(http.StatusOK, completion(valid, "stop"))(w, r)
	})
	ext, err := p.ReadLabel(context.Background(), testImage, analysis.RequestContext{Locale: "ru"})
	if err != nil {
		t.Fatalf("ReadLabel: %v", err)
	}
	if !ext.Found || ext.Basis != "per_100g" || ext.Protein == nil || *ext.Protein != 8.4 ||
		ext.Usage.InputTokens != 1500 || ext.Usage.OutputTokens != 220 {
		t.Errorf("extraction = %+v", ext)
	}
	wantImage := "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString(testImage.Data)
	for _, want := range []string{wantImage, "nutrition facts table", "nutrition_label_result", "json_schema", "Russian"} {
		if !strings.Contains(raw, want) {
			t.Errorf("request does not contain %q", want)
		}
	}
	if strings.Contains(raw, "food_vision_result") || strings.Contains(raw, "Identify each distinct food") {
		t.Error("a label request must not carry the meal instructions or schema")
	}
	if strings.Contains(raw, testKey) {
		t.Error("API key must not appear in the request body")
	}
}

func TestReadLabelAcceptsAFencedAnswer(t *testing.T) {
	t.Parallel()

	fenced := "```json\n" + string(testutil.Fixture(t, "ai-label-per-serving.json")) + "\n```"
	p := newProvider(t, respond(http.StatusOK, completion(fenced, "stop")))
	ext, err := p.ReadLabel(context.Background(), testImage, analysis.RequestContext{})
	if err != nil || ext.Basis != "per_serving" || ext.ServingSizeG == nil || *ext.ServingSizeG != 30 {
		t.Errorf("ext = %+v, err = %v", ext, err)
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
			p := newProvider(t, respond(http.StatusOK, completion(body, "stop")))
			if _, err := p.ReadLabel(context.Background(), testImage, analysis.RequestContext{}); !errors.Is(err, analysis.ErrInvalidResponse) {
				t.Errorf("err = %v, want ErrInvalidResponse", err)
			}
		})
	}
}

func TestReadLabelErrorClassification(t *testing.T) {
	t.Parallel()

	for status, want := range map[int]error{
		http.StatusTooManyRequests:     analysis.ErrUnavailable,
		http.StatusBadGateway:          analysis.ErrUnavailable,
		http.StatusPaymentRequired:     analysis.ErrRejected,
		http.StatusUnprocessableEntity: analysis.ErrRejected,
	} {
		p := newProvider(t, respond(status, `{"error":"secret detail"}`))
		_, err := p.ReadLabel(context.Background(), testImage, analysis.RequestContext{})
		if !errors.Is(err, want) {
			t.Errorf("status %d: err = %v, want %v", status, err, want)
		}
		if err != nil && strings.Contains(err.Error(), "secret detail") {
			t.Error("provider error bodies must not leak into errors")
		}
	}
}

// TestLabelResponseSchemaMatchesProtocol keeps the label schema in sync with
// the published JSON Schema: same properties and required lists.
func TestLabelResponseSchemaMatchesProtocol(t *testing.T) {
	t.Parallel()

	var proto map[string]any
	if err := json.Unmarshal(testutil.ReadProtocol(t, "ai/nutrition-label-result.schema.json"), &proto); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(openai.LabelResponseSchema())
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
