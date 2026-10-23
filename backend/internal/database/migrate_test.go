package database_test

import (
	"context"
	"fmt"
	"plany/internal/config"
	"plany/internal/database"
	"sync"
	"testing"
	"testing/fstest"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

// schemaPool returns a pool whose search_path is a throwaway schema (then public, for the citext
// extension), so each test migrates in isolation and never touches the real tables.
func schemaPool(t *testing.T, maxConns int32) (*pgxpool.Pool, string) {
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

	pc, err := pgxpool.ParseConfig(database.CreateConnString(cfg.Database))
	if err != nil {
		t.Fatalf("parse config: %v", err)
	}
	pc.MaxConns = maxConns
	pc.ConnConfig.RuntimeParams["search_path"] = schema + ",public"
	pool, err := pgxpool.NewWithConfig(ctx, pc)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool, schema
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

func files(sql ...string) fstest.MapFS {
	fsys := fstest.MapFS{}
	for i, body := range sql {
		fsys[fmt.Sprintf("%06d_step.up.sql", i+1)] = &fstest.MapFile{Data: []byte(body)}
	}
	// down files must be ignored
	fsys["000001_step.down.sql"] = &fstest.MapFile{Data: []byte("DROP TABLE nothing;")}
	return fsys
}

func TestDB_Migrate_AppliesInOrderAndIsIdempotent(t *testing.T) {
	pool, _ := schemaPool(t, 2)
	fsys := files(
		"CREATE TABLE a (id int); INSERT INTO a VALUES (1);",
		"CREATE TABLE b (id int); INSERT INTO b SELECT id FROM a;",
	)
	for i := 0; i < 3; i++ {
		if err := database.Migrate(context.Background(), pool, fsys); err != nil {
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

func TestDB_Migrate_ContinuesFromAHandMigratedDatabase(t *testing.T) {
	pool, _ := schemaPool(t, 2)
	ctx := context.Background()
	// what the golang-migrate CLI leaves behind after applying version 1 by hand
	if _, err := pool.Exec(ctx, `CREATE TABLE schema_migrations (version bigint NOT NULL PRIMARY KEY, dirty boolean NOT NULL);
		INSERT INTO schema_migrations VALUES (1, false); CREATE TABLE a (id int);`); err != nil {
		t.Fatal(err)
	}
	fsys := files("CREATE TABLE a (id int);", "CREATE TABLE b (id int);")
	if err := database.Migrate(ctx, pool, fsys); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if v, _ := version(t, pool); v != 2 {
		t.Fatalf("version = %d, want 2", v)
	}
	if n := count(t, pool, "b"); n != 0 {
		t.Fatalf("b should exist and be empty, got %d rows", n)
	}
}

func TestDB_Migrate_FailureRollsBackAndKeepsTheLastGoodVersion(t *testing.T) {
	pool, _ := schemaPool(t, 2)
	ctx := context.Background()
	broken := files("CREATE TABLE a (id int);", "CREATE TABLE b (id int); SELECT boom FROM nowhere;")
	if err := database.Migrate(ctx, pool, broken); err == nil {
		t.Fatal("a broken migration must fail")
	}
	if v, dirty := version(t, pool); v != 1 || dirty {
		t.Fatalf("version = %d dirty=%v, want 1 false", v, dirty)
	}
	var exists bool
	if err := pool.QueryRow(ctx, "SELECT to_regclass('b') IS NOT NULL").Scan(&exists); err != nil || exists {
		t.Fatalf("half-applied migration leaked table b (exists=%v err=%v)", exists, err)
	}
	// a fixed release picks up from there
	fixed := files("CREATE TABLE a (id int);", "CREATE TABLE b (id int);")
	if err := database.Migrate(ctx, pool, fixed); err != nil {
		t.Fatalf("fixed migrate: %v", err)
	}
	if v, _ := version(t, pool); v != 2 {
		t.Fatalf("version = %d, want 2", v)
	}
}

func TestDB_Migrate_RefusesADirtyDatabase(t *testing.T) {
	pool, _ := schemaPool(t, 2)
	ctx := context.Background()
	if _, err := pool.Exec(ctx, `CREATE TABLE schema_migrations (version bigint NOT NULL PRIMARY KEY, dirty boolean NOT NULL);
		INSERT INTO schema_migrations VALUES (1, true);`); err != nil {
		t.Fatal(err)
	}
	if err := database.Migrate(ctx, pool, files("CREATE TABLE a (id int);", "CREATE TABLE b (id int);")); err == nil {
		t.Fatal("a dirty database must be refused")
	}
	if v, dirty := version(t, pool); v != 1 || !dirty {
		t.Fatalf("a refused run must not touch the version: %d %v", v, dirty)
	}
}

func TestMigrate_RejectsBadFileNames(t *testing.T) {
	cases := map[string]fstest.MapFS{
		"no version":   {"init.up.sql": {Data: []byte("SELECT 1")}},
		"zero version": {"000000_init.up.sql": {Data: []byte("SELECT 1")}},
		"not a number": {"abc_init.up.sql": {Data: []byte("SELECT 1")}},
		"duplicate":    {"1_a.up.sql": {Data: []byte("SELECT 1")}, "000001_b.up.sql": {Data: []byte("SELECT 1")}},
	}
	for name, fsys := range cases {
		t.Run(name, func(t *testing.T) {
			// the names are checked before the database is touched, so no pool is needed
			if err := database.Migrate(context.Background(), nil, fsys); err == nil {
				t.Fatal("expected an error")
			}
		})
	}
}

func TestDB_Migrate_ReplicasStartingTogetherApplyEachMigrationOnce(t *testing.T) {
	pool, _ := schemaPool(t, 10)
	fsys := files("CREATE TABLE a (id int);", "INSERT INTO a VALUES (1);", "INSERT INTO a VALUES (2);")

	var wg sync.WaitGroup
	errs := make(chan error, 10)
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs <- database.Migrate(context.Background(), pool, fsys)
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

func TestDB_Migrate_CancelledContextFailsInsteadOfHanging(t *testing.T) {
	pool, _ := schemaPool(t, 2)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := database.Migrate(ctx, pool, files("CREATE TABLE a (id int);")); err == nil {
		t.Fatal("expected an error with a cancelled context")
	}
}

func TestDB_Migrate_ShippedMigrationsApplyOnAnEmptySchema(t *testing.T) {
	pool, _ := schemaPool(t, 2)
	ctx := context.Background()
	if err := database.Migrate(ctx, pool, database.Migrations()); err != nil {
		t.Fatalf("shipped migrations: %v", err)
	}
	for _, table := range []string{"users", "notes", "revoked_tokens"} {
		var ok bool
		if err := pool.QueryRow(ctx, "SELECT to_regclass($1) IS NOT NULL", table).Scan(&ok); err != nil || !ok {
			t.Fatalf("table %s missing after migrating (err=%v)", table, err)
		}
	}
	// and a second start is a no-op
	if err := database.Migrate(ctx, pool, database.Migrations()); err != nil {
		t.Fatalf("second run: %v", err)
	}
}
