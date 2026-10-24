package database_test

import (
	"context"
	"errors"
	"plany/internal/config"
	"plany/internal/database"
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

// Stress: a client that opens connections and never finishes its query (the "slow or
// never-finished requests" case from CLAUDE.md). It must not crash the pool or let the
// legitimate request hang forever: a request with its own deadline should fail on time, and
// the pool must recover once that client goes away.
func TestDB_Pool_NeverFinishingConnectionsBoundLegitimateWait(t *testing.T) {
	const maxConns = 2
	pool := smallPool(t, maxConns)
	bg := context.Background()

	// the greedy client: holds every connection in the pool without ever releasing it
	held := make([]*pgxpool.Conn, 0, maxConns)
	for i := 0; i < maxConns; i++ {
		conn, err := pool.Acquire(bg)
		if err != nil {
			t.Fatalf("greedy client acquire %d: %v", i, err)
		}
		held = append(held, conn)
	}
	if got := pool.Stat().AcquiredConns(); got != int32(maxConns) {
		t.Fatalf("expected the pool fully held, got %d/%d acquired", got, maxConns)
	}

	// the victim: a normal request, but it must not wait forever
	victimCtx, cancel := context.WithTimeout(bg, 400*time.Millisecond)
	defer cancel()
	start := time.Now()
	_, err := pool.Acquire(victimCtx)
	waited := time.Since(start)

	if err == nil {
		t.Fatal("victim request got a connection while the pool was fully held: should have waited and timed out")
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Errorf("victim error = %v, want context.DeadlineExceeded (a clean timeout, not a crash)", err)
	}
	if waited > 2*time.Second {
		t.Errorf("victim waited %v past its own 400ms deadline: the deadline was not honored", waited)
	}

	// greedy client disconnects (e.g. the connection dies or is finally closed); the pool must recover
	for _, conn := range held {
		conn.Release()
	}
	recoverCtx, recoverCancel := context.WithTimeout(bg, 2*time.Second)
	defer recoverCancel()
	conn, err := pool.Acquire(recoverCtx)
	if err != nil {
		t.Fatalf("pool did not recover after that client released its connections: %v", err)
	}
	conn.Release()
}

// Careless/unusual use: acquiring with an already-cancelled context must fail immediately
// (not block, not silently succeed and leak a connection the caller never expects to release).
func TestDB_Pool_AcquireWithCancelledContext_FailsWithoutLeaking(t *testing.T) {
	pool := smallPool(t, 2)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	start := time.Now()
	_, err := pool.Acquire(ctx)
	elapsed := time.Since(start)

	if err == nil {
		t.Fatal("acquire with a cancelled context should fail, not succeed")
	}
	if elapsed > 500*time.Millisecond {
		t.Errorf("acquire with a cancelled context took %v, should fail immediately", elapsed)
	}
	if got := pool.Stat().AcquiredConns(); got != 0 {
		t.Fatalf("%d connections acquired despite the failed call: a leak", got)
	}
}

// A burst of failed/cancelled acquires, repeated, must not slowly leak connections either
// (e.g. a client opening and abandoning many requests in a row).
func TestDB_Pool_RepeatedCancelledAcquires_NeverLeak(t *testing.T) {
	pool := smallPool(t, 2)

	for i := 0; i < 200; i++ {
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		if _, err := pool.Acquire(ctx); err == nil {
			t.Fatalf("iteration %d: acquire unexpectedly succeeded with a cancelled context", i)
		}
	}
	if got := pool.Stat().AcquiredConns(); got != 0 {
		t.Fatalf("%d connections acquired after 200 cancelled attempts: a slow leak", got)
	}

	// the pool must still work normally afterwards
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var one int
	if err := pool.QueryRow(ctx, "SELECT 1").Scan(&one); err != nil || one != 1 {
		t.Fatalf("pool unusable after the cancelled-acquire flood: %v", err)
	}
}

// Stress: each of several concurrent "clients" cancels its own context mid-flood while others
// keep running real queries. One client giving up must not disturb the others.
func TestDB_Pool_MixedCancelledAndLiveQueries_IsolatedPerCaller(t *testing.T) {
	pool := smallPool(t, 3)
	const n = 30

	var wg sync.WaitGroup
	var liveFailures, cancelledSuccesses int32
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			if i%3 == 0 {
				// a client that gives up immediately
				ctx, cancel := context.WithCancel(context.Background())
				cancel()
				if err := pool.QueryRow(ctx, "SELECT pg_sleep(0.01)").Scan(new(interface{})); err == nil {
					atomic.AddInt32(&cancelledSuccesses, 1)
				}
				return
			}
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			var one int
			if err := pool.QueryRow(ctx, "SELECT 1").Scan(&one); err != nil || one != 1 {
				atomic.AddInt32(&liveFailures, 1)
			}
		}(i)
	}
	wg.Wait()

	if liveFailures != 0 {
		t.Fatalf("%d legitimate queries failed because other callers cancelled theirs", liveFailures)
	}
	if cancelledSuccesses != 0 {
		t.Fatalf("%d cancelled queries somehow succeeded", cancelledSuccesses)
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
