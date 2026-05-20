package reviews

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
)

// OpenDB opens a PostgreSQL connection. Returns a non-nil error when the DSN
// is empty or the connection cannot be established.
func OpenDB(dsn string) (*sql.DB, error) {
	if dsn == "" {
		return nil, sql.ErrNoRows // sentinel: no DSN configured
	}
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

// SoloDimensions holds averaged per-dimension scores aggregated from reviews_extracted.
type SoloDimensions struct {
	Wifi     float64 `json:"wifi"`
	Noise    float64 `json:"noise"`
	Seating  float64 `json:"seating"`
	Staff    float64 `json:"staff"`
	Lighting float64 `json:"lighting"`
	Safety   float64 `json:"safety"`
}

// HandleGetSoloScore handles GET /v1/experiences/:id/solo-score.
// Reads from reviews_extracted aggregated by experience_id (mean per dimension).
// Returns 404 when no rows exist for the given experience.
func HandleGetSoloScore(c *gin.Context, db *sql.DB) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "experience id required"})
		return
	}

	row := db.QueryRowContext(c.Request.Context(), `
		SELECT
			COUNT(*),
			COALESCE(AVG(wifi_score), 0),
			COALESCE(AVG(noise_score), 0),
			COALESCE(AVG(seating_score), 0),
			COALESCE(AVG(staff_score), 0),
			COALESCE(AVG(lighting_score), 0),
			COALESCE(AVG(safety_score), 0)
		FROM reviews_extracted
		WHERE experience_id = $1
	`, id)

	var count int
	var dims SoloDimensions
	if err := row.Scan(&count, &dims.Wifi, &dims.Noise, &dims.Seating, &dims.Staff, &dims.Lighting, &dims.Safety); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "query failed"})
		return
	}

	if count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "no reviews found for experience"})
		return
	}

	confidence := computeConfidence(count)

	c.JSON(http.StatusOK, gin.H{
		"experience_id": id,
		"dimensions":    dims,
		"sample_count":  count,
		"confidence":    confidence,
	})
}

// computeConfidence returns a 0–1 confidence score based on sample count.
func computeConfidence(count int) float64 {
	switch {
	case count >= 20:
		return 1.0
	case count >= 10:
		return 0.8
	case count >= 5:
		return 0.6
	case count >= 2:
		return 0.4
	default:
		return 0.2
	}
}
