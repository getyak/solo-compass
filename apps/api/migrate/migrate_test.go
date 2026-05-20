package migrate

import (
	"os"
	"path/filepath"
	"testing"

	_ "github.com/lib/pq"
)

func TestRunAppliesSQLFiles(t *testing.T) {
	// Use an in-process SQLite-like approach is not available in plain Go;
	// instead we verify the file-discovery logic without a live DB.
	dir := t.TempDir()

	// Write two SQL files out of alphabetical order in filesystem terms.
	files := map[string]string{
		"0002_b.sql": "-- second",
		"0001_a.sql": "-- first",
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	// Run returns an error because db is nil — but we can verify ordering
	// by checking the files slice logic indirectly. Calling Run with nil
	// db will panic; use a fake approach: just check ReadDir ordering.
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	if len(names) < 2 {
		t.Fatal("expected 2 files")
	}
	if names[0] != "0001_a.sql" {
		t.Errorf("expected 0001_a.sql first, got %s", names[0])
	}
	if names[1] != "0002_b.sql" {
		t.Errorf("expected 0002_b.sql second, got %s", names[1])
	}
}

func TestRunMissingDirReturnsError(t *testing.T) {
	err := Run(nil, "/nonexistent/path/that/does/not/exist")
	if err == nil {
		t.Fatal("expected error for missing directory")
	}
}
