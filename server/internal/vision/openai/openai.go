// Package openai implements analysis.FoodVisionProvider for services that speak
// the OpenAI "chat completions" protocol with image input, such as OpenRouter
// and RouterAI. One implementation serves all of them; only the base URL, the
// model and the API key differ.
package openai

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
	"example.com/calsnap/server/internal/app/label"
	"example.com/calsnap/server/internal/vision/prompt"
)

// maxResponseBytes bounds the provider response body.
const maxResponseBytes = 2 << 20

// maxOutputTokens leaves room for 20 items with names in two languages.
const maxOutputTokens = 2048

// Config configures the provider.
type Config struct {
	BaseURL string // e.g. https://openrouter.ai/api/v1 (without /chat/completions)
	Model   string
	APIKey  string
}

// Provider calls a chat-completions endpoint. It is safe for concurrent use.
type Provider struct {
	cfg    Config
	client *http.Client
}

var (
	_ analysis.FoodVisionProvider = (*Provider)(nil)
	_ label.Reader                = (*Provider)(nil)
)

// New creates a Provider that sends requests with client, which must have a
// timeout configured.
func New(cfg Config, client *http.Client) *Provider {
	cfg.BaseURL = strings.TrimRight(cfg.BaseURL, "/")
	return &Provider{cfg: cfg, client: client}
}

// Analyze implements analysis.FoodVisionProvider.
//
// NOTE: the request id is not forwarded: the protocol has no request metadata
// field, and the routing services would only see it as an unknown header.
func (p *Provider) Analyze(ctx context.Context, img analysis.Image, rc analysis.RequestContext) (analysis.Result, error) {
	text, usage, err := p.chat(ctx, p.buildRequest(img, rc))
	if err != nil {
		return analysis.Result{}, err
	}
	res, err := analysis.ParseResult([]byte(extractJSON(text)))
	if err != nil {
		return analysis.Result{}, err
	}
	res.Usage = usage
	return res, nil
}

// ReadLabel implements label.Reader: it transcribes the nutrition table on a
// package photo.
func (p *Provider) ReadLabel(ctx context.Context, img analysis.Image, rc analysis.RequestContext) (label.Extraction, error) {
	text, usage, err := p.chat(ctx, p.buildLabelRequest(img, rc))
	if err != nil {
		return label.Extraction{}, err
	}
	ext, err := label.ParseExtraction([]byte(extractJSON(text)))
	if err != nil {
		return label.Extraction{}, err
	}
	ext.Usage = usage
	return ext, nil
}

// chat sends one chat-completions request and returns the message text.
func (p *Provider) chat(ctx context.Context, request map[string]any) (string, analysis.Usage, error) {
	body, err := json.Marshal(request)
	if err != nil {
		return "", analysis.Usage{}, fmt.Errorf("encode chat request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.cfg.BaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", analysis.Usage{}, fmt.Errorf("build chat request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// The key travels in a header, never in the URL, because URLs get logged.
	req.Header.Set("Authorization", "Bearer "+p.cfg.APIKey)

	resp, err := p.client.Do(req)
	if err != nil {
		var uerr *url.Error
		if errors.As(err, &uerr) {
			err = uerr.Err // drop the URL from the message
		}
		return "", analysis.Usage{}, fmt.Errorf("%w: chat request failed: %w", analysis.ErrUnavailable, err)
	}
	defer resp.Body.Close()

	// Error bodies are drained but never included in errors or logs.
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes+1))
	if err != nil {
		return "", analysis.Usage{}, fmt.Errorf("%w: reading chat response: %w", analysis.ErrUnavailable, err)
	}
	if err := classifyStatus(resp.StatusCode); err != nil {
		return "", analysis.Usage{}, err
	}
	if len(data) > maxResponseBytes {
		return "", analysis.Usage{}, fmt.Errorf("%w: response exceeds %d bytes", analysis.ErrInvalidResponse, maxResponseBytes)
	}
	return parseEnvelope(data)
}

// classifyStatus maps HTTP statuses: 408, 429 and 5xx are transient, other
// non-200 statuses (bad request, bad key, no credit, moderation) are not.
func classifyStatus(status int) error {
	switch {
	case status == http.StatusOK:
		return nil
	case status == http.StatusRequestTimeout, status == http.StatusTooManyRequests, status >= 500:
		return fmt.Errorf("%w: provider returned HTTP %d", analysis.ErrUnavailable, status)
	default:
		return fmt.Errorf("%w: provider returned HTTP %d", analysis.ErrRejected, status)
	}
}

type chatResponse struct {
	Choices []struct {
		Message struct {
			Content json.RawMessage `json:"content"`
		} `json:"message"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	// Routers such as OpenRouter may answer 200 and report an upstream failure here.
	Error *struct {
		Code json.RawMessage `json:"code"`
	} `json:"error"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
	} `json:"usage"`
}

// parseEnvelope extracts the message text and the token usage from a
// chat-completions response.
func parseEnvelope(data []byte) (string, analysis.Usage, error) {
	var cr chatResponse
	if err := json.Unmarshal(data, &cr); err != nil {
		return "", analysis.Usage{}, fmt.Errorf("%w: chat envelope: %v", analysis.ErrInvalidResponse, err)
	}
	if cr.Error != nil {
		return "", analysis.Usage{}, classifyEmbeddedError(cr.Error.Code)
	}
	if len(cr.Choices) == 0 {
		return "", analysis.Usage{}, fmt.Errorf("%w: no choices returned", analysis.ErrInvalidResponse)
	}
	choice := cr.Choices[0]
	if choice.FinishReason == "length" || choice.FinishReason == "content_filter" {
		return "", analysis.Usage{}, fmt.Errorf("%w: finish reason %s", analysis.ErrInvalidResponse, choice.FinishReason)
	}
	text, err := contentText(choice.Message.Content)
	if err != nil {
		return "", analysis.Usage{}, err
	}
	return text, analysis.Usage{InputTokens: cr.Usage.PromptTokens, OutputTokens: cr.Usage.CompletionTokens}, nil
}

// classifyEmbeddedError treats an error object inside an HTTP 200 like the
// equivalent status: a numeric code of 408, 429 or 5xx is transient.
func classifyEmbeddedError(code json.RawMessage) error {
	var n int
	if err := json.Unmarshal(code, &n); err == nil {
		return classifyStatus(n)
	}
	return fmt.Errorf("%w: provider reported an error", analysis.ErrRejected)
}

// contentText returns the message text. Most services send a string; some send
// a list of typed parts.
func contentText(raw json.RawMessage) (string, error) {
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return s, nil
	}
	var parts []struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(raw, &parts); err != nil {
		return "", fmt.Errorf("%w: unexpected message content", analysis.ErrInvalidResponse)
	}
	var b strings.Builder
	for _, p := range parts {
		b.WriteString(p.Text)
	}
	return b.String(), nil
}

// extractJSON strips a Markdown code fence that models without native JSON
// output often wrap around the answer.
func extractJSON(text string) string {
	t := strings.TrimSpace(text)
	if !strings.HasPrefix(t, "```") {
		return t
	}
	t = strings.TrimPrefix(t, "```")
	if nl := strings.IndexByte(t, '\n'); nl >= 0 {
		t = t[nl+1:] // drop the language tag line ("json")
	}
	t = strings.TrimSuffix(strings.TrimSpace(t), "```")
	return strings.TrimSpace(t)
}

func imagePart(img analysis.Image) map[string]any {
	dataURL := "data:" + img.MIMEType + ";base64," + base64.StdEncoding.EncodeToString(img.Data)
	return map[string]any{"type": "image_url", "image_url": map[string]any{"url": dataURL}}
}

func (p *Provider) buildRequest(img analysis.Image, rc analysis.RequestContext) map[string]any {
	content := []any{
		map[string]any{"type": "text", "text": prompt.User(rc)},
		imagePart(img),
	}
	if rc.SideImage != nil {
		content = append(content, imagePart(*rc.SideImage))
	}
	return p.chatRequest(prompt.System, content, "food_vision_result", ResponseSchema())
}

func (p *Provider) buildLabelRequest(img analysis.Image, rc analysis.RequestContext) map[string]any {
	content := []any{
		map[string]any{"type": "text", "text": prompt.LabelUser(rc)},
		imagePart(img),
	}
	return p.chatRequest(prompt.LabelSystem, content, "nutrition_label_result", LabelResponseSchema())
}

func (p *Provider) chatRequest(system string, content []any, schemaName string, schema map[string]any) map[string]any {
	return map[string]any{
		"model": p.cfg.Model,
		"messages": []any{
			map[string]any{"role": "system", "content": system},
			map[string]any{"role": "user", "content": content},
		},
		"temperature": 0.2,
		"max_tokens":  maxOutputTokens,
		// Not strict: the contract has optional properties, which strict mode forbids.
		// Models without structured output support still follow the prompt.
		"response_format": map[string]any{
			"type": "json_schema",
			"json_schema": map[string]any{
				"name":   schemaName,
				"strict": false,
				"schema": schema,
			},
		},
	}
}

// LabelResponseSchema returns the JSON Schema sent as response_format for a
// nutrition label. It mirrors protocol/ai/nutrition-label-result.schema.json.
func LabelResponseSchema() map[string]any {
	num := map[string]any{"type": "number", "minimum": 0}
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"properties": map[string]any{
			"found":         map[string]any{"type": "boolean"},
			"productName":   map[string]any{"type": "string", "maxLength": 100},
			"basis":         map[string]any{"type": "string", "enum": []any{"per_100g", "per_100ml", "per_serving"}},
			"servingSizeG":  map[string]any{"type": "number", "exclusiveMinimum": 0, "maximum": 2000},
			"energyKcal":    num,
			"energyKj":      num,
			"protein":       num,
			"fat":           num,
			"carbohydrates": num,
			"confidence":    map[string]any{"type": "number", "minimum": 0, "maximum": 1},
		},
		"required": []any{"found", "confidence"},
	}
}

// ResponseSchema returns the JSON Schema sent as response_format. It mirrors
// protocol/ai/food-vision-result.schema.json (a test keeps them in sync).
func ResponseSchema() map[string]any {
	num := map[string]any{"type": "number"}
	str := map[string]any{"type": "string"}
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"properties": map[string]any{
			"items": map[string]any{
				"type":     "array",
				"maxItems": 20,
				"items": map[string]any{
					"type":                 "object",
					"additionalProperties": false,
					"properties": map[string]any{
						"name":             str,
						"displayName":      str,
						"estimatedWeightG": map[string]any{"type": "number", "exclusiveMinimum": 0, "maximum": 3000},
						"confidence":       map[string]any{"type": "number", "minimum": 0, "maximum": 1},
						"cookingMethod":    str,
						"nutritionPer100g": map[string]any{
							"type":                 "object",
							"additionalProperties": false,
							"properties":           map[string]any{"kcal": num, "protein": num, "fat": num, "carbs": num},
							"required":             []any{"kcal", "protein", "fat", "carbs"},
						},
					},
					"required": []any{"name", "displayName", "estimatedWeightG", "confidence"},
				},
			},
		},
		"required": []any{"items"},
	}
}
