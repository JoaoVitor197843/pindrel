package database_test

import (
	"context"
	"pindrel/internal/config"
	"pindrel/internal/database"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

// smallPool loads the real config but shrinks MaxConns, so a concurrency test can reliably
// oversubscribe the pool without needing hundreds of goroutines. The override only touches
// this in-memory copy of cfg.Database; it does not change the running .env or other tests.
func smallPool(t *testing.T, maxConns int) *pgxpool.Pool {
	t.Helper()
	godotenv.Load("../../.env")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("error on creating configuration: %v", err)
	}
	cfg.Database.MaxConns = maxConns

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	pool, err := database.NewConnection(ctx, cfg.Database)
	if err != nil {
		t.Fatalf("error on postgres connection: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// Stress: a flood of concurrent requests, many more than the pool's MaxConns, each running a
// real query. pgxpool must queue the extra ones rather than fail them or let any of them leak
// a connection. This is the "many concurrent requests hitting one pool" DoS described in
// CLAUDE.md, at the connection-pool layer instead of the HTTP layer.
func TestDB_Pool_FloodOfQueriesQueuesInsteadOfFailing(t *testing.T) {
	const maxConns = 3
	const flood = 60 // 20x the pool size
	pool := smallPool(t, maxConns)

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	var wg sync.WaitGroup
	var failures int32
	var peakAcquired int32
	start := time.Now()
	for i := 0; i < flood; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var one int
			// a short query stands in for a real handler's DB call under load
			if err := pool.QueryRow(ctx, "SELECT 1").Scan(&one); err != nil || one != 1 {
				atomic.AddInt32(&failures, 1)
				return
			}
			if acquired := pool.Stat().AcquiredConns(); acquired > atomic.LoadInt32(&peakAcquired) {
				atomic.StoreInt32(&peakAcquired, acquired)
			}
		}()
	}
	wg.Wait()
	elapsed := time.Since(start)

	if failures != 0 {
		t.Fatalf("%d/%d queries failed under the flood (pool exhaustion must queue, not error)", failures, flood)
	}
	if peakAcquired > maxConns {
		t.Fatalf("peak acquired connections = %d, want <= MaxConns (%d): the pool let more through than configured", peakAcquired, maxConns)
	}
	if elapsed > 10*time.Second {
		t.Errorf("flood took %v for %d trivial queries over %d connections: looks stuck, not just queued", elapsed, flood, maxConns)
	}
	if stat := pool.Stat(); stat.AcquiredConns() != 0 {
		t.Fatalf("%d connections still acquired after the flood finished: a leak", stat.AcquiredConns())
	}
}

// Sanity check that smallPool's override actually takes effect, so the concurrency tests above are
// exercising the limit they claim to.
func TestDB_Pool_MaxConnsOverrideTakesEffect(t *testing.T) {
	for _, max := range []int{1, 5} {
		pool := smallPool(t, max)
		if got := pool.Stat().MaxConns(); got != int32(max) {
			t.Errorf("MaxConns=%d: pool reports %d", max, got)
		}
	}
}
