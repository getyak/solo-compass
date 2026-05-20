// Package migrate applies SQL migration files in lexicographic order.
package migrate

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Run applies every *.sql file in migrationsDir to db, in lexicographic order.
// It is idempotent: migration files must use CREATE IF NOT EXISTS / CREATE EXTENSION IF NOT EXISTS.
func Run(db *sql.DB, migrationsDir string) error {
	entries, err := os.ReadDir(migrationsDir)
	if err != nil {
		return fmt.Errorf("migrate: read dir %q: %w", migrationsDir, err)
	}

	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			files = append(files, filepath.Join(migrationsDir, e.Name()))
		}
	}
	sort.Strings(files)

	for _, f := range files {
		sql, err := os.ReadFile(f)
		if err != nil {
			return fmt.Errorf("migrate: read %q: %w", f, err)
		}
		if _, err := db.Exec(string(sql)); err != nil {
			return fmt.Errorf("migrate: exec %q: %w", f, err)
		}
	}
	return nil
}
