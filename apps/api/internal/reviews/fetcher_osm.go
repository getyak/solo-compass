package reviews

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

var osmNotesEndpoint = "https://api.openstreetmap.org/api/0.6/notes.json"

// setOSMNotesEndpoint overrides the endpoint URL for testing.
func setOSMNotesEndpoint(u string) { osmNotesEndpoint = u }

// Review holds a single review-like record pulled from an external source.
type Review struct {
	Source    string
	RawText   string
	Lat       float64
	Lon       float64
	CreatedAt time.Time
}

// BBox defines a geographic bounding box for the OSM notes query.
type BBox struct {
	MinLon, MinLat, MaxLon, MaxLat float64
}

type osmNotesResponse struct {
	Features []struct {
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
	} `json:"features"`
}

// FetchOSMNotes fetches public OSM notes within bbox via the OSM Notes API.
// The context is respected for cancellation; a 30-second timeout is applied
// on top of whatever deadline the caller provides.
func FetchOSMNotes(ctx context.Context, bbox BBox, limit int) ([]Review, error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	params := url.Values{}
	params.Set("bbox", fmt.Sprintf("%.6f,%.6f,%.6f,%.6f", bbox.MinLon, bbox.MinLat, bbox.MaxLon, bbox.MaxLat))
	params.Set("limit", fmt.Sprintf("%d", limit))
	params.Set("closed", "0")

	reqURL := osmNotesEndpoint + "?" + params.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("fetcher_osm: build request: %w", err)
	}
	req.Header.Set("Accept", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetcher_osm: http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetcher_osm: upstream status %d", resp.StatusCode)
	}

	var result osmNotesResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("fetcher_osm: decode: %w", err)
	}

	return parseOSMNotes(result), nil
}

func parseOSMNotes(result osmNotesResponse) []Review {
	reviews := make([]Review, 0, len(result.Features))
	for _, f := range result.Features {
		if len(f.Geometry.Coordinates) < 2 {
			continue
		}
		lon := f.Geometry.Coordinates[0]
		lat := f.Geometry.Coordinates[1]

		// Collect text from "opened" comments.
		for _, c := range f.Properties.Comments {
			if c.Action != "opened" || c.Text == "" {
				continue
			}
			createdAt, _ := time.Parse("2006-01-02 15:04:05 UTC", f.Properties.DateCreated)
			reviews = append(reviews, Review{
				Source:    "osm",
				RawText:   c.Text,
				Lat:       lat,
				Lon:       lon,
				CreatedAt: createdAt,
			})
		}
	}
	return reviews
}
