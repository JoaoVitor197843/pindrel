package database

import (
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"os"
	"strings"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5" // registers the pgx5:// scheme
	"github.com/golang-migrate/migrate/v4/source"
	"github.com/golang-migrate/migrate/v4/source/iofs"
)

// The migrations ship inside the binary. golang-migrate (the CLI on the developer's machine and this library)
// applies them: `migrate -path internal/database/migrations -database "$URL" up` does the same by hand.
//
//go:embed migrations/*.sql
var embeddedMigrations embed.FS

// Migrations is the embedded migrations directory (NNNNNN_name.up.sql / .down.sql).
func Migrations() fs.FS {
	sub, err := fs.Sub(embeddedMigrations, "migrations")
	if err != nil {
		panic(err) // the directory is embedded above: cannot happen
	}
	return sub
}

// Migrate brings the database at dsn (the postgres:// URL of CreateConnString) up to date with the embedded
// migrations. It runs once at startup of every API replica: golang-migrate takes a Postgres advisory lock, so
// replicas starting together wait for each other and the second one finds nothing left to do.
func Migrate(dsn string) error { return MigrateFS(dsn, Migrations()) }

// MigrateFS is Migrate for any directory of migrations (the tests use throwaway ones).
//
// golang-migrate marks the database "dirty" before running a file and clears it only if the file succeeds, so a
// failed migration leaves it dirty and every later start refuses to run. That would turn one bad release into a
// database that nothing can start on, even the previous release the deploy rolls back to. It is safe to recover
// automatically here because of an invariant of this repository: each migration file is ONE implicit transaction
// (Postgres runs a multi-statement query as one; the files have no BEGIN/COMMIT and nothing that cannot run in a
// transaction, which TestMigrationsAreAtomic enforces), so a file that failed changed nothing. Dirty at version V
// therefore means "V did not apply": the version goes back to the one before V and the migrations run again.
func MigrateFS(dsn string, fsys fs.FS) error {
	src, err := iofs.New(fsys, ".")
	if err != nil {
		return fmt.Errorf("migrate: read migrations: %w", err)
	}
	m, err := migrate.NewWithSourceInstance("iofs", src, "pgx5://"+strings.TrimPrefix(strings.TrimPrefix(dsn, "postgresql://"), "postgres://"))
	if err != nil {
		return fmt.Errorf("migrate: connect: %w", err)
	}
	defer m.Close()

	err = m.Up()
	var dirty migrate.ErrDirty
	if errors.As(err, &dirty) {
		prev, perr := versionBefore(src, uint(dirty.Version))
		if perr != nil {
			return fmt.Errorf("migrate: %w", perr)
		}
		log.Printf("migrate: version %d was left dirty by a failed migration (atomic, nothing applied): back to %d", dirty.Version, prev)
		if ferr := m.Force(prev); ferr != nil {
			return fmt.Errorf("migrate: force %d: %w", prev, ferr)
		}
		err = m.Up()
	}
	if errors.Is(err, migrate.ErrNoChange) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	log.Println("migrate: database is up to date")
	return nil
}

// versionBefore is the greatest version of src below v (-1, golang-migrate's NilVersion, if there is none). It looks at
// the files that exist now: the dirty version may belong to a release whose file was removed.
func versionBefore(src source.Driver, v uint) (int, error) {
	prev := -1 // golang-migrate's NilVersion: no migration applied
	next, err := src.First()
	for err == nil && next < v {
		prev = int(next)
		next, err = src.Next(next)
	}
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return 0, err
	}
	return prev, nil
}
