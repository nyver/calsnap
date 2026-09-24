// Package gemini implements analysis.FoodVisionProvider on top of the Gemini
// generateContent REST API. It uses plain net/http instead of an SDK to keep the
// dependency footprint small and to control body limits and retries.
package gemini

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/vision/prompt"
)

// maxResponseBytes bounds the provider response body.
const maxResponseBytes = 2 << 20

// maxOutputTokens leaves room for 20 items with names in two languages.
const maxOutputTokens = 2048

// Config configures the provider.
type Config struct {
	BaseURL string // e.g. https://generativelanguage.googleapis.com/v1beta
	Model   string
	APIKey  string
}

// Provider calls Gemini. It is safe for concurrent use.
type Provider struct {
	cfg    Config
	client *http.Client
}

var _ analysis.FoodVisionProvider = (*Provider)(nil)

// New creates a Provider that sends requests with client, which must have a
// timeout configured.
func New(cfg Config, client *http.Client) *Provider {
	cfg.BaseURL = strings.TrimRight(cfg.BaseURL, "/")
	return &Provider{cfg: cfg, client: client}
}

// Analyze implements analysis.FoodVisionProvider.
//
// NOTE: the request id is not forwarded to Gemini: the Gemini Developer API has
// no request metadata field, and unknown headers would only add noise.
func (p *Provider) Analyze(ctx context.Context, img analysis.Image, rc analysis.RequestContext) (analysis.Result, error) {
	body, err := json.Marshal(buildRequest(img, rc))
	if err != nil {
		return analysis.Result{}, fmt.Errorf("encode gemini request: %w", err)
	}
	endpoint := p.cfg.BaseURL + "/models/" + url.PathEscape(p.cfg.Model) + ":generateContent"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return analysis.Result{}, fmt.Errorf("build gemini request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	// The key travels in a header, never in the URL, because URLs get logged.
	httpReq.Header.Set("x-goog-api-key", p.cfg.APIKey)

	resp, err := p.client.Do(httpReq)
	if err != nil {
		var uerr *url.Error
		if errors.As(err, &uerr) {
			err = uerr.Err // drop the URL from the message
		}
		return analysis.Result{}, fmt.Errorf("%w: gemini request failed: %w", analysis.ErrUnavailable, err)
	}
	defer resp.Body.Close()

	// Error bodies are drained but never included in errors or logs.
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes+1))
	if err != nil {
		return analysis.Result{}, fmt.Errorf("%w: reading gemini response: %w", analysis.ErrUnavailable, err)
	}
	switch {
	case resp.StatusCode == http.StatusOK:
	case resp.StatusCode == http.StatusRequestTimeout, resp.StatusCode == http.StatusTooManyRequests, resp.StatusCode >= 500:
		return analysis.Result{}, fmt.Errorf("%w: gemini returned HTTP %d", analysis.ErrUnavailable, resp.StatusCode)
	default:
		return analysis.Result{}, fmt.Errorf("%w: gemini returned HTTP %d", analysis.ErrRejected, resp.StatusCode)
	}
	if len(data) > maxResponseBytes {
		return analysis.Result{}, fmt.Errorf("%w: gemini response exceeds %d bytes", analysis.ErrInvalidResponse, maxResponseBytes)
	}
	return parseResponse(data)
}

type generateResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
		FinishReason string `json:"finishReason"`
	} `json:"candidates"`
	PromptFeedback struct {
		BlockReason string `json:"blockReason"`
	} `json:"promptFeedback"`
	UsageMetadata struct {
		PromptTokenCount     int `json:"promptTokenCount"`
		CandidatesTokenCount int `json:"candidatesTokenCount"`
	} `json:"usageMetadata"`
}

func parseResponse(data []byte) (analysis.Result, error) {
	var gr generateResponse
	if err := json.Unmarshal(data, &gr); err != nil {
		return analysis.Result{}, fmt.Errorf("%w: gemini envelope: %v", analysis.ErrInvalidResponse, err)
	}
	if gr.PromptFeedback.BlockReason != "" {
		return analysis.Result{}, fmt.Errorf("%w: prompt blocked (%s)", analysis.ErrRejected, gr.PromptFeedback.BlockReason)
	}
	if len(gr.Candidates) == 0 {
		return analysis.Result{}, fmt.Errorf("%w: gemini returned no candidates", analysis.ErrInvalidResponse)
	}
	cand := gr.Candidates[0]
	if cand.FinishReason != "" && cand.FinishReason != "STOP" {
		return analysis.Result{}, fmt.Errorf("%w: gemini finish reason %s", analysis.ErrInvalidResponse, cand.FinishReason)
	}
	var text strings.Builder
	for _, part := range cand.Content.Parts {
		text.WriteString(part.Text)
	}
	res, err := analysis.ParseResult([]byte(text.String()))
	if err != nil {
		return analysis.Result{}, err
	}
	res.Usage = analysis.Usage{
		InputTokens:  gr.UsageMetadata.PromptTokenCount,
		OutputTokens: gr.UsageMetadata.CandidatesTokenCount,
	}
	return res, nil
}

func buildRequest(img analysis.Image, rc analysis.RequestContext) map[string]any {
	parts := []any{
		map[string]any{"text": prompt.User(rc)},
		inlineImage(img),
	}
	if rc.SideImage != nil {
		parts = append(parts, inlineImage(*rc.SideImage))
	}
	return map[string]any{
		"systemInstruction": map[string]any{
			"parts": []any{map[string]any{"text": prompt.System}},
		},
		"contents": []any{map[string]any{
			"role":  "user",
			"parts": parts,
		}},
		"generationConfig": map[string]any{
			"responseMimeType": "application/json",
			"responseSchema":   ResponseSchema(),
			"temperature":      0.2,
			"maxOutputTokens":  maxOutputTokens,
		},
	}
}

func inlineImage(img analysis.Image) map[string]any {
	return map[string]any{"inlineData": map[string]any{
		"mimeType": img.MIMEType,
		"data":     base64.StdEncoding.EncodeToString(img.Data),
	}}
}

// ResponseSchema returns the Gemini responseSchema equivalent of
// protocol/ai/food-vision-result.schema.json (the Gemini schema dialect does
// not support additionalProperties or exclusive bounds).
func ResponseSchema() map[string]any {
	num := map[string]any{"type": "NUMBER"}
	str := map[string]any{"type": "STRING"}
	return map[string]any{
		"type": "OBJECT",
		"properties": map[string]any{
			"items": map[string]any{
				"type":     "ARRAY",
				"maxItems": 20,
				"items": map[string]any{
					"type": "OBJECT",
					"properties": map[string]any{
						"name":             str,
						"displayName":      str,
						"estimatedWeightG": map[string]any{"type": "NUMBER", "minimum": 0, "maximum": 3000},
						"confidence":       map[string]any{"type": "NUMBER", "minimum": 0, "maximum": 1},
						"cookingMethod":    str,
						"nutritionPer100g": map[string]any{
							"type": "OBJECT",
							"properties": map[string]any{
								"kcal": num, "protein": num, "fat": num, "carbs": num,
							},
							"required": []any{"kcal", "protein", "fat", "carbs"},
						},
					},
					"required": []any{"name", "displayName", "estimatedWeightG", "confidence"},
				},
			},
		},
		"required": []any{"items"},
	}
}
