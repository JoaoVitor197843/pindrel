package database_test

import (
	"context"
	"fmt"
	"io/fs"
	"net/url"
	"pindrel/internal/config"
	"pindrel/internal/database"
	"regexp"
	"strings"
	"sync"
	"testing"
	"testing/fstest"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

// schemaDB creates a throwaway schema (search_path = it, then public, for the citext extension) so each test
// migrates in isolation and never touches the real tables. It returns the DSN that points at it and a pool for
// inspecting the result.
func schemaDB(t *testing.T) (string, *pgxpool.Pool) {
	t.Helper()
	godotenv.Load("../../.env")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("error on creating configuration: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	admin, err := database.NewConnection(ctx, cfg.Database)
	if err != nil {
		t.Fatalf("failed to connect to postgres: %v", err)
	}
	schema := "migtest_" + uuid.NewString()[:8]
	if _, err := admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		admin.Close()
		t.Fatalf("create schema: %v", err)
	}
	t.Cleanup(func() {
		_, _ = admin.Exec(context.Background(), "DROP SCHEMA "+schema+" CASCADE")
		admin.Close()
	})

	u, err := url.Parse(database.CreateConnString(cfg.Database))
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	q.Set("search_path", schema+",public")
	u.RawQuery = q.Encode()
	dsn := u.String()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return dsn, pool
}

func version(t *testing.T, pool *pgxpool.Pool) (int64, bool) {
	t.Helper()
	var v int64
	var dirty bool
	if err := pool.QueryRow(context.Background(), "SELECT version, dirty FROM schema_migrations").Scan(&v, &dirty); err != nil {
		t.Fatalf("read schema_migrations: %v", err)
	}
	return v, dirty
}

func count(t *testing.T, pool *pgxpool.Pool, table string) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(), "SELECT count(*) FROM "+table).Scan(&n); err != nil {
		t.Fatalf("count %s: %v", table, err)
	}
	return n
}

func exists(t *testing.T, pool *pgxpool.Pool, table string) bool {
	t.Helper()
	var ok bool
	if err := pool.QueryRow(context.Background(), "SELECT to_regclass($1) IS NOT NULL", table).Scan(&ok); err != nil {
		t.Fatal(err)
	}
	return ok
}

// files builds a migrations directory: sql[i] is version i+1 (plus a down file that must be ignored).
func files(sql ...string) fstest.MapFS {
	fsys := fstest.MapFS{}
	for i, body := range sql {
		fsys[fmt.Sprintf("%06d_step.up.sql", i+1)] = &fstest.MapFile{Data: []byte(body)}
		fsys[fmt.Sprintf("%06d_step.down.sql", i+1)] = &fstest.MapFile{Data: []byte("DROP TABLE nothing;")}
	}
	return fsys
}

func TestDB_Migrate_AppliesInOrderAndIsIdempotent(t *testing.T) {
	dsn, pool := schemaDB(t)
	fsys := files(
		"CREATE TABLE a (id int); INSERT INTO a VALUES (1);",
		"CREATE TABLE b (id int); INSERT INTO b SELECT id FROM a;",
	)
	for i := 0; i < 3; i++ {
		if err := database.MigrateFS(dsn, fsys); err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
	}
	if v, dirty := version(t, pool); v != 2 || dirty {
		t.Fatalf("version = %d dirty=%v, want 2 false", v, dirty)
	}
	if count(t, pool, "a") != 1 || count(t, pool, "b") != 1 {
		t.Fatal("each migration must run exactly once, in order")
	}
}

func TestDB_Migrate_ContinuesFromABaselinedDatabase(t *testing.T) {
	dsn, pool := schemaDB(t)
	ctx := context.Background()
	// a database migrated by hand and then baselined with `migrate force 1`
	if _, err := pool.Exec(ctx, `CREATE TABLE schema_migrations (version bigint NOT NULL PRIMARY KEY, dirty boolean NOT NULL);
		INSERT INTO schema_migrations VALUES (1, false); CREATE TABLE a (id int);`); err != nil {
		t.Fatal(err)
	}
	if err := database.MigrateFS(dsn, files("CREATE TABLE a (id int);", "CREATE TABLE b (id int);")); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if v, _ := version(t, pool); v != 2 {
		t.Fatalf("version = %d, want 2", v)
	}
	if !exists(t, pool, "b") {
		t.Fatal("b should exist")
	}
}

// The failed file changed nothing (it is one implicit transaction) and the database must not stay dirty:
// the previous release is rolled back onto it, and the fixed release must be able to start.
func TestDB_Migrate_FailedMigrationLeavesNothingAndTheNextReleaseRecovers(t *testing.T) {
	dsn, pool := schemaDB(t)
	broken := files("CREATE TABLE a (id int);", "CREATE TABLE b (id int); SELECT boom FROM nowhere;")
	if err := database.MigrateFS(dsn, broken); err == nil {
		t.Fatal("a broken migration must fail")
	}
	if exists(t, pool, "b") {
		t.Fatal("half-applied migration leaked table b")
	}
	// the previous release (only version 1) starts on the database the failure left behind
	if err := database.MigrateFS(dsn, files("CREATE TABLE a (id int);")); err != nil {
		t.Fatalf("the previous release must still start: %v", err)
	}
	if v, dirty := version(t, pool); v != 1 || dirty {
		t.Fatalf("after recovery version = %d dirty=%v, want 1 false", v, dirty)
	}
	// and a fixed release picks up from there
	if err := database.MigrateFS(dsn, files("CREATE TABLE a (id int);", "CREATE TABLE b (id int);")); err != nil {
		t.Fatalf("fixed release: %v", err)
	}
	if v, dirty := version(t, pool); v != 2 || dirty || !exists(t, pool, "b") {
		t.Fatalf("version = %d dirty=%v b=%v, want 2 false true", v, dirty, exists(t, pool, "b"))
	}
}

func TestDB_Migrate_FailedFirstMigrationRecoversToEmpty(t *testing.T) {
	dsn, pool := schemaDB(t)
	if err := database.MigrateFS(dsn, files("SELECT boom FROM nowhere;")); err == nil {
		t.Fatal("a broken migration must fail")
	}
	if err := database.MigrateFS(dsn, files("CREATE TABLE a (id int);")); err != nil {
		t.Fatalf("fixed release: %v", err)
	}
	if v, dirty := version(t, pool); v != 1 || dirty {
		t.Fatalf("version = %d dirty=%v, want 1 false", v, dirty)
	}
}

func TestDB_Migrate_ReplicasStartingTogetherApplyEachMigrationOnce(t *testing.T) {
	dsn, pool := schemaDB(t)
	fsys := files("CREATE TABLE a (id int);", "INSERT INTO a VALUES (1);", "INSERT INTO a VALUES (2);")

	var wg sync.WaitGroup
	errs := make(chan error, 10)
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs <- database.MigrateFS(dsn, fsys)
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatalf("concurrent migrate: %v", err)
		}
	}
	if v, _ := version(t, pool); v != 3 {
		t.Fatalf("version = %d, want 3", v)
	}
	if n := count(t, pool, "a"); n != 2 {
		t.Fatalf("rows = %d, want 2 (a migration ran twice or not at all)", n)
	}
}

func TestDB_Migrate_ShippedMigrationsApplyOnAnEmptySchema(t *testing.T) {
	dsn, pool := schemaDB(t)
	if err := database.Migrate(dsn); err != nil {
		t.Fatalf("shipped migrations: %v", err)
	}
	for _, table := range []string{"users", "notes", "revoked_tokens"} {
		if !exists(t, pool, table) {
			t.Fatalf("table %s missing after migrating", table)
		}
	}
	if err := database.Migrate(dsn); err != nil { // a second start is a no-op
		t.Fatalf("second run: %v", err)
	}
}

func TestMigrate_UnreachableDatabaseIsAnError(t *testing.T) {
	if err := database.MigrateFS("postgres://nobody:x@127.0.0.1:1/none?sslmode=disable&connect_timeout=2", files("SELECT 1;")); err == nil {
		t.Fatal("expected an error")
	}
}

// The automatic recovery from a dirty database is only sound if a failed file changes nothing, which holds when
// every file is a single implicit transaction: no BEGIN/COMMIT/ROLLBACK, and no statement Postgres refuses to run
// inside a transaction block.
func TestMigrationsAreAtomic(t *testing.T) {
	forbidden := regexp.MustCompile(`(?i)\b(begin|start\s+transaction|commit|rollback|savepoint|vacuum|concurrently|create\s+database|drop\s+database|alter\s+system)\b`)
	comment := regexp.MustCompile(`(?m)--.*$`)
	n := 0
	err := fs.WalkDir(database.Migrations(), ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".sql") {
			return err
		}
		n++
		body, err := fs.ReadFile(database.Migrations(), path)
		if err != nil {
			return err
		}
		if m := forbidden.FindString(comment.ReplaceAllString(string(body), "")); m != "" {
			t.Errorf("%s uses %q: a migration must be one implicit transaction (see database.MigrateFS)", path, m)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if n < 2 {
		t.Fatalf("found %d migration files, the embed is broken", n)
	}
}
