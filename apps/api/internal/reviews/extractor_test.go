package reviews

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"
)

type mockHTTPClient struct {
	status   int
	body     string
	err      error
	lastReq  *http.Request
	lastBody []byte
}

func (m *mockHTTPClient) Do(req *http.Request) (*http.Response, error) {
	m.lastReq = req
	if req.Body != nil {
		body, _ := io.ReadAll(req.Body)
		m.lastBody = body
	}
	if m.err != nil {
		return nil, m.err
	}
	return &http.Response{
		StatusCode: m.status,
		Body:       io.NopCloser(bytes.NewBufferString(m.body)),
	}, nil
}

// chatResponse builds an OpenAI-compatible chat/completions envelope.
func chatResponse(content string) string {
	payload := map[string]any{
		"choices": []map[string]any{
			{"message": map[string]any{"content": content}},
		},
		"usage": map[string]int{"prompt_tokens": 5, "completion_tokens": 6},
	}
	b, err := json.Marshal(payload)
	if err != nil {
		panic(err)
	}
	return string(b)
}

const scoresJSON = `{"wifi_score":8.0,"noise_score":7.5,"seating_score":9.0,"staff_score":6.0,"lighting_score":7.0,"safety_score":8.5,"summary":"Quiet cafe, great for solo work"}`

func TestExtract_SuccessPath(t *testing.T) {
	mock := &mockHTTPClient{status: http.StatusOK, body: chatResponse(scoresJSON)}
	ext := newExtractorWithClient("test-key", mock, "https://api.deepseek.com/v1/chat/completions")

	scores, err := ext.Extract(context.Background(), "Great cafe for solo work, free wifi")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if scores.WifiScore != 8.0 {
		t.Errorf("wifi_score: expected 8.0, got %f", scores.WifiScore)
	}
	if scores.SafetyScore != 8.5 {
		t.Errorf("safety_score: expected 8.5, got %f", scores.SafetyScore)
	}
	if scores.Summary == "" {
		t.Error("summary must not be empty")
	}
}

func TestExtract_WireBodyAndAuth(t *testing.T) {
	mock := &mockHTTPClient{status: http.StatusOK, body: chatResponse(scoresJSON)}
	ext := newExtractorWithClient("sk-test-key", mock, "https://api.deepseek.com/v1/chat/completions")

	if _, err := ext.Extract(context.Background(), "some review"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if mock.lastReq == nil {
		t.Fatal("expected an HTTP request")
	}
	if got := mock.lastReq.Header.Get("Authorization"); got != "Bearer sk-test-key" {
		t.Errorf("Authorization header: expected Bearer sk-test-key, got %q", got)
	}
	if got := mock.lastReq.Header.Get("Content-Type"); got != "application/json" {
		t.Errorf("Content-Type header: expected application/json, got %q", got)
	}
	if got := mock.lastReq.URL.String(); got != "https://api.deepseek.com/v1/chat/completions" {
		t.Errorf("URL: expected DeepSeek chat/completions, got %q", got)
	}

	var body map[string]any
	if err := json.Unmarshal(mock.lastBody, &body); err != nil {
		t.Fatalf("decode request body: %v", err)
	}
	if body["model"] != "deepseek-flash" {
		t.Errorf("model: expected deepseek-flash, got %v", body["model"])
	}
	thinking, ok := body["thinking"].(map[string]any)
	if !ok || thinking["type"] != "disabled" {
		t.Errorf("expected top-level thinking {type:disabled}, got %v", body["thinking"])
	}
	responseFormat, ok := body["response_format"].(map[string]any)
	if !ok || responseFormat["type"] != "json_object" {
		t.Errorf("expected response_format {type:json_object}, got %v", body["response_format"])
	}
	if _, nested := body["extra_body"]; nested {
		t.Error("thinking must be top-level; extra_body must not be sent")
	}
	if _, ok := body["messages"]; !ok {
		t.Error("expected messages in request body")
	}
}

func TestExtract_MissingAPIKey(t *testing.T) {
	ext := newExtractorWithClient("", &mockHTTPClient{}, "https://api.deepseek.com/v1/chat/completions")
	_, err := ext.Extract(context.Background(), "some text")
	if err == nil {
		t.Fatal("expected error for missing API key")
	}
}

func TestExtract_Non200Response(t *testing.T) {
	ext := newExtractorWithClient("test-key", &mockHTTPClient{
		status: http.StatusTooManyRequests,
		body:   `{"error":"rate limited"}`,
	}, "https://api.deepseek.com/v1/chat/completions")

	_, err := ext.Extract(context.Background(), "some text")
	if err == nil {
		t.Fatal("expected error for non-200 status")
	}
}

func TestExtract_MalformedJSON(t *testing.T) {
	ext := newExtractorWithClient("test-key", &mockHTTPClient{
		status: http.StatusOK,
		body:   chatResponse("not valid json"),
	}, "https://api.deepseek.com/v1/chat/completions")

	_, err := ext.Extract(context.Background(), "some text")
	if err == nil {
		t.Fatal("expected error for malformed JSON in text field")
	}
}

func TestExtract_EmptyContentResponse(t *testing.T) {
	ext := newExtractorWithClient("test-key", &mockHTTPClient{
		status: http.StatusOK,
		body:   `{"choices":[]}`,
	}, "https://api.deepseek.com/v1/chat/completions")

	_, err := ext.Extract(context.Background(), "some text")
	if err == nil {
		t.Fatal("expected error for empty content")
	}
}

func TestExtract_EmptyMessageContent(t *testing.T) {
	ext := newExtractorWithClient("test-key", &mockHTTPClient{
		status: http.StatusOK,
		body:   chatResponse(""),
	}, "https://api.deepseek.com/v1/chat/completions")

	_, err := ext.Extract(context.Background(), "some text")
	if err == nil {
		t.Fatal("expected error for empty message content")
	}
}

func TestNormalizeDeepSeekModel(t *testing.T) {
	legacy := []string{"deepseek-chat", "deepseek-reasoner", "deepseek-v4-pro", "deepseek-v4-flash", "", "  "}
	for _, id := range legacy {
		if got := normalizeDeepSeekModel(id); got != "deepseek-flash" {
			t.Errorf("normalizeDeepSeekModel(%q): expected deepseek-flash, got %q", id, got)
		}
	}
	if got := normalizeDeepSeekModel("my-fine-tune"); got != "my-fine-tune" {
		t.Errorf("expected custom model preserved, got %q", got)
	}
}

func TestDeepSeekChatURL(t *testing.T) {
	t.Setenv("DEEPSEEK_BASE_URL", "")
	if got := deepSeekChatURL(); got != "https://api.deepseek.com/v1/chat/completions" {
		t.Errorf("default URL: got %q", got)
	}

	t.Setenv("DEEPSEEK_BASE_URL", "https://proxy.example.com/v1///")
	if got := deepSeekChatURL(); got != "https://proxy.example.com/v1/chat/completions" {
		t.Errorf("custom URL: got %q", got)
	}
}

func TestNewExtractor_NormalizesLegacyEnvModel(t *testing.T) {
	t.Setenv("DEEPSEEK_API_KEY", "sk-env")
	t.Setenv("DEEPSEEK_MODEL", "deepseek-v4-pro")
	t.Setenv("DEEPSEEK_BASE_URL", "")

	ext := NewExtractor()
	if ext.model != "deepseek-flash" {
		t.Errorf("NewExtractor model: expected deepseek-flash, got %q", ext.model)
	}
	if ext.apiURL != "https://api.deepseek.com/v1/chat/completions" {
		t.Errorf("NewExtractor apiURL: got %q", ext.apiURL)
	}
}
