package database

import (
	"context"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"sort"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.up.sql
var embeddedMigrations embed.FS

// Migrations are the schema migrations that ship inside the binary (migrations/*.up.sql).
func Migrations() fs.FS {
	sub, err := fs.Sub(embeddedMigrations, "migrations")
	if err != nil {
		panic(err) // the directory is embedded above: cannot happen
	}
	return sub
}

// migrationLockKey is the Postgres advisory lock that serializes replicas starting at the same time.
const migrationLockKey = 7_062_201_551

type migration struct {
	version int64
	name    string
}

// Migrate applies, in order, every `NNNNNN_name.up.sql` of fsys whose version is greater than the one
// recorded in schema_migrations. The table has the same layout as golang-migrate's (one row with the
// current version and a dirty flag), so a database migrated by hand with that tool carries on from where
// it is. Each file runs in its own transaction together with the version bump, so a failure leaves the
// schema at the last good version; a database marked dirty is refused rather than guessed at.
//
// Safe to call from several replicas at once: they wait for each other on an advisory lock, and the ones
// that come second find nothing left to do.
func Migrate(ctx context.Context, pool *pgxpool.Pool, fsys fs.FS) error {
	migrations, err := listMigrations(fsys)
	if err != nil {
		return err
	}

	conn, err := pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("migrate: acquire connection: %w", err)
	}
	defer conn.Release()

	if _, err := conn.Exec(ctx, "SELECT pg_advisory_lock($1)", migrationLockKey); err != nil {
		return fmt.Errorf("migrate: lock: %w", err)
	}
	defer func() {
		// the lock is per session and the connection goes back to the pool: release it explicitly
		if _, err := conn.Exec(context.WithoutCancel(ctx), "SELECT pg_advisory_unlock($1)", migrationLockKey); err != nil {
			log.Printf("migrate: unlock: %v", err)
		}
	}()

	if _, err := conn.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (version bigint NOT NULL PRIMARY KEY, dirty boolean NOT NULL)`); err != nil {
		return fmt.Errorf("migrate: create schema_migrations: %w", err)
	}

	var current int64
	var dirty bool
	err = conn.QueryRow(ctx, `SELECT version, dirty FROM schema_migrations LIMIT 1`).Scan(&current, &dirty)
	hasRow := err == nil
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return fmt.Errorf("migrate: read version: %w", err)
	}
	if dirty {
		return fmt.Errorf("migrate: schema_migrations is dirty at version %d; fix the database by hand", current)
	}

	for _, m := range migrations {
		if m.version <= current {
			continue
		}
		body, err := fs.ReadFile(fsys, m.name)
		if err != nil {
			return fmt.Errorf("migrate: read %s: %w", m.name, err)
		}
		tx, err := conn.Begin(ctx)
		if err != nil {
			return fmt.Errorf("migrate: begin %s: %w", m.name, err)
		}
		if _, err := tx.Exec(ctx, string(body)); err != nil {
			_ = tx.Rollback(ctx)
			if !hasRow {
				return fmt.Errorf("migrate: apply %s: %w (if this database was migrated by hand, record its version first: "+
					"CREATE TABLE schema_migrations (version bigint NOT NULL PRIMARY KEY, dirty boolean NOT NULL); "+
					"INSERT INTO schema_migrations VALUES (<last applied version>, false); see deploy/README.md)", m.name, err)
			}
			return fmt.Errorf("migrate: apply %s: %w", m.name, err)
		}
		bump := `INSERT INTO schema_migrations (version, dirty) VALUES ($1, false)`
		if hasRow {
			bump = `UPDATE schema_migrations SET version = $1, dirty = false`
		}
		if _, err := tx.Exec(ctx, bump, m.version); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("migrate: record %s: %w", m.name, err)
		}
		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("migrate: commit %s: %w", m.name, err)
		}
		hasRow = true
		current = m.version
		log.Printf("migrate: applied %s", m.name)
	}
	return nil
}

func listMigrations(fsys fs.FS) ([]migration, error) {
	files, err := fs.Glob(fsys, "*.up.sql")
	if err != nil {
		return nil, fmt.Errorf("migrate: list: %w", err)
	}
	seen := map[int64]string{}
	var out []migration
	for _, name := range files {
		prefix, _, ok := strings.Cut(name, "_")
		version, err := strconv.ParseInt(prefix, 10, 64)
		if !ok || err != nil || version <= 0 {
			return nil, fmt.Errorf("migrate: %q does not start with a positive NNNNNN_ version", name)
		}
		if other, dup := seen[version]; dup {
			return nil, fmt.Errorf("migrate: %q and %q share version %d", other, name, version)
		}
		seen[version] = name
		out = append(out, migration{version: version, name: name})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].version < out[j].version })
	return out, nil
}
