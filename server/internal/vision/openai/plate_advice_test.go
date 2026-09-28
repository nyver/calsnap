package openai_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/plateadvice"
	"example.com/calsnap/server/internal/testutil"
	"example.com/calsnap/server/internal/vision/openai"
)

func testAdviceInput() plateadvice.Input {
	return plateadvice.Input{
		Locale:   analysis.LocaleRU,
		MealType: plateadvice.MealLunch,
		Items: []plateadvice.Item{
			{Name: "Гречка", WeightG: 180, PlateGroup: plateadvice.GroupComplexCarbohydrate},
		},
		Balance: plateadvice.Balance{
			VegetablesFruit:      plateadvice.StatusLow,
			Protein:              plateadvice.StatusOK,
			ComplexCarbohydrates: plateadvice.StatusOK,
		},
	}
}

func TestAdviseSuccessAndRequestShape(t *testing.T) {
	t.Parallel()

	var raw string
	var body map[string]any
	valid := string(testutil.Fixture(t, "ai-plate-advice-valid-ru.json"))
	p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		raw = string(b)
		_ = json.Unmarshal(b, &body)
		respond(http.StatusOK, completion(valid, "stop"))(w, r)
	})

	advice, err := p.Advise(context.Background(), testAdviceInput())
	if err != nil {
		t.Fatalf("Advise: %v", err)
	}
	if advice.Summary == "" || len(advice.Suggestions) == 0 {
		t.Errorf("advice = %+v", advice)
	}
	if advice.Usage.InputTokens != 1500 || advice.Usage.OutputTokens != 220 {
		t.Errorf("usage = %+v", advice.Usage)
	}

	for _, want := range []string{"Гречка", "plate_advice_result", "json_schema", "Russian", "BEGIN_MEAL_DATA"} {
		if !strings.Contains(raw, want) {
			t.Errorf("request does not contain %q: %s", want, raw)
		}
	}
	if strings.Contains(raw, "image_url") {
		t.Error("a plate advice request must not carry an image part")
	}
	if body["max_tokens"] != float64(1024) {
		t.Errorf("max_tokens = %v, want 1024", body["max_tokens"])
	}
	if strings.Contains(raw, testKey) {
		t.Error("API key must not appear in the request body")
	}
}

func TestAdviseAcceptsAFencedAnswer(t *testing.T) {
	t.Parallel()

	fenced := "```json\n" + string(testutil.Fixture(t, "ai-plate-advice-valid-en.json")) + "\n```"
	p := newProvider(t, respond(http.StatusOK, completion(fenced, "stop")))
	advice, err := p.Advise(context.Background(), testAdviceInput())
	if err != nil || advice.Summary == "" {
		t.Errorf("advice = %+v, err = %v", advice, err)
	}
}

func TestAdviseRejectsInvalidAnswers(t *testing.T) {
	t.Parallel()

	for _, fixture := range []string{
		"ai-plate-advice-invalid-too-many.json",
		"ai-plate-advice-invalid-unknown-action.json",
		"ai-plate-advice-invalid-unknown-field.json",
		"ai-plate-advice-invalid-long-title.json",
		"ai-plate-advice-invalid-missing-reason.json",
	} {
		t.Run(fixture, func(t *testing.T) {
			t.Parallel()
			body := string(testutil.Fixture(t, fixture))
			p := newProvider(t, respond(http.StatusOK, completion(body, "stop")))
			if _, err := p.Advise(context.Background(), testAdviceInput()); !errors.Is(err, analysis.ErrInvalidResponse) {
				t.Errorf("err = %v, want ErrInvalidResponse", err)
			}
		})
	}
}

func TestAdviseErrorClassification(t *testing.T) {
	t.Parallel()

	for status, want := range map[int]error{
		http.StatusTooManyRequests:     analysis.ErrUnavailable,
		http.StatusBadGateway:          analysis.ErrUnavailable,
		http.StatusPaymentRequired:     analysis.ErrRejected,
		http.StatusUnprocessableEntity: analysis.ErrRejected,
	} {
		p := newProvider(t, respond(status, `{"error":"secret detail"}`))
		_, err := p.Advise(context.Background(), testAdviceInput())
		if !errors.Is(err, want) {
			t.Errorf("status %d: err = %v, want %v", status, err, want)
		}
		if err != nil && strings.Contains(err.Error(), "secret detail") {
			t.Error("provider error bodies must not leak into errors")
		}
	}
}

// TestPlateAdviceResponseSchemaMatchesProtocol keeps the schema in sync with
// the published JSON Schema: same properties and required lists.
func TestPlateAdviceResponseSchemaMatchesProtocol(t *testing.T) {
	t.Parallel()

	var proto map[string]any
	if err := json.Unmarshal(testutil.ReadProtocol(t, "ai/plate-advice-result.schema.json"), &proto); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(openai.PlateAdviceResponseSchema())
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

	psi, _ := pp["suggestions"].(map[string]any)
	gsi, _ := gp["suggestions"].(map[string]any)
	pItem, _ := psi["items"].(map[string]any)
	gItem, _ := gsi["items"].(map[string]any)
	if names(pItem["required"]) != names(gItem["required"]) {
		t.Errorf("suggestion required %s != %s", names(pItem["required"]), names(gItem["required"]))
	}
	pip, _ := pItem["properties"].(map[string]any)
	gip, _ := gItem["properties"].(map[string]any)
	if keys(pip) != keys(gip) {
		t.Errorf("suggestion properties %s != %s", keys(pip), keys(gip))
	}
}
