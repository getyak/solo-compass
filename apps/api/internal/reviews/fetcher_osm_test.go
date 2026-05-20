package reviews

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

func TestFetchOSMNotes_FixtureResponse(t *testing.T) {
	fixture, err := os.ReadFile("testdata/osm_notes_fixture.json")
	if err != nil {
		t.Fatalf("load fixture: %v", err)
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write(fixture)
	}))
	defer srv.Close()

	// Swap the endpoint for the test server.
	original := osmNotesEndpoint
	setOSMNotesEndpoint(srv.URL)
	defer setOSMNotesEndpoint(original)

	bbox := BBox{MinLon: 98.9, MinLat: 18.7, MaxLon: 99.1, MaxLat: 18.9}
	reviews, err := FetchOSMNotes(context.Background(), bbox, 10)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(reviews) != 2 {
		t.Fatalf("expected 2 reviews, got %d", len(reviews))
	}
	for _, r := range reviews {
		if r.Source != "osm" {
			t.Errorf("expected source 'osm', got %q", r.Source)
		}
		if r.RawText == "" {
			t.Error("raw_text must not be empty")
		}
		if r.Lat == 0 || r.Lon == 0 {
			t.Errorf("lat/lon must be non-zero, got lat=%f lon=%f", r.Lat, r.Lon)
		}
		if r.CreatedAt.IsZero() {
			t.Error("created_at must be parsed")
		}
	}
}

func TestFetchOSMNotes_ContextCancelled(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(200 * time.Millisecond)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	original := osmNotesEndpoint
	setOSMNotesEndpoint(srv.URL)
	defer setOSMNotesEndpoint(original)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()

	_, err := FetchOSMNotes(ctx, BBox{}, 5)
	if err == nil {
		t.Fatal("expected error from cancelled context")
	}
}

func TestFetchOSMNotes_Non200Status(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	original := osmNotesEndpoint
	setOSMNotesEndpoint(srv.URL)
	defer setOSMNotesEndpoint(original)

	_, err := FetchOSMNotes(context.Background(), BBox{}, 5)
	if err == nil {
		t.Fatal("expected error for non-200 status")
	}
}

func TestParseOSMNotes_FiltersEmptyText(t *testing.T) {
	result := osmNotesResponse{}
	result.Features = []struct {
		Geometry struct {
			Coordinates []float64 `json:"coordinates"`
		} `json:"geometry"`
		Properties struct {
			DateCreated string `json:"date_created"`
			Comments    []struct {
				Text   string `json:"text"`
				Action string `json:"action"`
			} `json:"comments"`
		} `json:"properties"`
	}{
		{
			Geometry: struct {
				Coordinates []float64 `json:"coordinates"`
			}{Coordinates: []float64{98.99, 18.78}},
			Properties: struct {
				DateCreated string `json:"date_created"`
				Comments    []struct {
					Text   string `json:"text"`
					Action string `json:"action"`
				} `json:"comments"`
			}{
				DateCreated: "2024-01-01 10:00:00 UTC",
				Comments: []struct {
					Text   string `json:"text"`
					Action string `json:"action"`
				}{
					{Text: "", Action: "opened"},
					{Text: "has text", Action: "commented"},
					{Text: "valid note", Action: "opened"},
				},
			},
		},
	}

	reviews := parseOSMNotes(result)
	if len(reviews) != 1 {
		t.Fatalf("expected 1 review (filtered empty + non-opened), got %d", len(reviews))
	}
	if reviews[0].RawText != "valid note" {
		t.Errorf("unexpected text: %q", reviews[0].RawText)
	}
}
