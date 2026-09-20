package reviews

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
)

const defaultDeepSeekBaseURL = "https://api.deepseek.com/v1"
const defaultDeepSeekModel = "deepseek-flash"

// legacyDeepSeekModels are pre-V4.1 ids that must not keep a built-in route on
// an outdated model. A saved legacy selection or an old DEEPSEEK_MODEL secret
// normalizes forward to deepseek-flash.
var legacyDeepSeekModels = map[string]bool{
	"deepseek-chat":     true,
	"deepseek-reasoner": true,
	"deepseek-v4-pro":   true,
	"deepseek-v4-flash": true,
}

// normalizeDeepSeekModel maps legacy / empty ids to the built-in default and
// passes explicitly configured non-legacy ids through.
func normalizeDeepSeekModel(raw string) string {
	model := strings.TrimSpace(raw)
	if model == "" || legacyDeepSeekModels[model] {
		return defaultDeepSeekModel
	}
	return model
}

// deepSeekChatURL resolves the OpenAI-compatible /chat/completions endpoint
// from DEEPSEEK_BASE_URL, defaulting to DeepSeek's public API.
func deepSeekChatURL() string {
	base := strings.TrimSpace(os.Getenv("DEEPSEEK_BASE_URL"))
	if base == "" {
		base = defaultDeepSeekBaseURL
	}
	return strings.TrimRight(base, "/") + "/chat/completions"
}

// ExtractedScores holds the structured solo-traveler metrics from one review.
type ExtractedScores struct {
	WifiScore     float64 `json:"wifi_score"`
	NoiseScore    float64 `json:"noise_score"`
	SeatingScore  float64 `json:"seating_score"`
	StaffScore    float64 `json:"staff_score"`
	LightingScore float64 `json:"lighting_score"`
	SafetyScore   float64 `json:"safety_score"`
	Summary       string  `json:"summary"`
}

// HTTPDoer abstracts http.Client for testing.
type HTTPDoer interface {
	Do(*http.Request) (*http.Response, error)
}

// Extractor calls DeepSeek's OpenAI-compatible chat/completions API to extract
// solo metrics from text. Thinking mode is explicitly disabled because the
// response parser only reads message.content (not reasoning_content).
type Extractor struct {
	apiKey string
	client HTTPDoer
	apiURL string
	model  string
}

// NewExtractor creates an Extractor reading DEEPSEEK_API_KEY from env.
func NewExtractor() *Extractor {
	return &Extractor{
		apiKey: os.Getenv("DEEPSEEK_API_KEY"),
		client: http.DefaultClient,
		apiURL: deepSeekChatURL(),
		model:  normalizeDeepSeekModel(os.Getenv("DEEPSEEK_MODEL")),
	}
}

// newExtractorWithClient creates an Extractor with a custom HTTP client (for tests).
func newExtractorWithClient(apiKey string, client HTTPDoer, apiURL string) *Extractor {
	return &Extractor{
		apiKey: apiKey,
		client: client,
		apiURL: apiURL,
		model:  defaultDeepSeekModel,
	}
}

var extractionPrompt = `You are a solo-travel data extractor. Given a review text, output ONLY a JSON object with these fields (all floats 0-10, higher = better for solo travelers):

{
  "wifi_score": <0-10>,
  "noise_score": <0-10, higher = quieter>,
  "seating_score": <0-10, higher = more solo-friendly seating>,
  "staff_score": <0-10, higher = more welcoming staff>,
  "lighting_score": <0-10, higher = better lighting>,
  "safety_score": <0-10, higher = safer>,
  "summary": "<one sentence summary for solo travelers>"
}

If a dimension is not mentioned, output 5.0. Output ONLY the JSON object, no other text.`

// Extract calls DeepSeek to extract structured scores from rawText.
func (e *Extractor) Extract(ctx context.Context, rawText string) (ExtractedScores, error) {
	if e.apiKey == "" {
		return ExtractedScores{}, fmt.Errorf("extractor: DEEPSEEK_API_KEY not set")
	}

	body := map[string]any{
		"model":      e.model,
		"max_tokens": 256,
		// Guarantee JSON-only output for the content-only parser.
		"response_format": map[string]string{"type": "json_object"},
		// DeepSeek V4.1 enables "high" thinking by default; we disable it with a
		// top-level wire field (never nested under extra_body) so latency and
		// the content-only parser stay as before.
		"thinking": map[string]string{"type": "disabled"},
		"messages": []map[string]string{
			{"role": "user", "content": extractionPrompt + "\n\nReview:\n" + rawText},
		},
	}
	bodyBytes, err := json.Marshal(body)
	if err != nil {
		return ExtractedScores{}, fmt.Errorf("extractor: marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, e.apiURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return ExtractedScores{}, fmt.Errorf("extractor: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+e.apiKey)

	resp, err := e.client.Do(req)
	if err != nil {
		return ExtractedScores{}, fmt.Errorf("extractor: http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return ExtractedScores{}, fmt.Errorf("extractor: upstream status %d", resp.StatusCode)
	}

	var apiResp struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return ExtractedScores{}, fmt.Errorf("extractor: decode response: %w", err)
	}

	if len(apiResp.Choices) == 0 || apiResp.Choices[0].Message.Content == "" {
		return ExtractedScores{}, fmt.Errorf("extractor: empty content from API")
	}

	text := apiResp.Choices[0].Message.Content
	var scores ExtractedScores
	if err := json.Unmarshal([]byte(text), &scores); err != nil {
		return ExtractedScores{}, fmt.Errorf("extractor: parse scores JSON %q: %w", text, err)
	}
	return scores, nil
}
