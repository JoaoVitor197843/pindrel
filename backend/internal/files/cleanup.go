package files

import (
	"context"
	"log"
	"os"
	"time"

	"pindrel/internal/database/db"

	"github.com/google/uuid"
)

// advisoryKey names the clean-up in the database: only one replica at a time does it.
const advisoryKey int64 = 0x70696e6c66696c73 // "pinlfils"

// CleanupStats is what one pass removed.
type CleanupStats struct {
	ExpiredUploads int
	Orphans        int
	StrayDirs      int
	StrayTmp       int
	StrayBlobs     int
}

// Cleanup removes what nothing needs any more: uploads nobody finished, files whose grace period as an orphan is over,
// and leftovers of a crash. It is safe to run on several replicas at once because each step claims its rows.
func (s *Service) Cleanup(ctx context.Context) (CleanupStats, error) {
	var st CleanupStats
	for {
		ids, err := s.q.ExpiredUploads(ctx, 100)
		if err != nil {
			return st, err
		}
		for _, id := range ids {
			if err := s.q.DeleteUploadByID(ctx, id); err != nil {
				return st, err
			}
			_ = s.store.RemoveUpload(id)
			st.ExpiredUploads++
		}
		if len(ids) < 100 {
			break
		}
	}
	for {
		due, err := s.q.OrphanFilesDue(ctx, db.OrphanFilesDueParams{OrphanSince: ts(s.now().Add(-s.cfg.OrphanGrace)), Limit: 100})
		if err != nil {
			return st, err
		}
		for _, f := range due {
			if err := s.removeOrphan(ctx, f.ID, f.Sha256); err != nil {
				return st, err
			}
			st.Orphans++
		}
		if len(due) < 100 {
			break
		}
	}
	dirs, tmps, err := s.store.StrayUploadDirs(s.cfg.UploadTTL + time.Hour)
	if err != nil {
		return st, err
	}
	for _, id := range dirs {
		known, err := s.q.UploadExists(ctx, id)
		if err != nil {
			return st, err
		}
		if !known {
			_ = s.store.RemoveUpload(id)
			st.StrayDirs++
		}
	}
	for _, p := range tmps {
		if os.Remove(p) == nil {
			st.StrayTmp++
		}
	}
	// walking every blob is the dearest step, so it runs once a day
	if s.now().Sub(s.lastSweep) >= 24*time.Hour {
		if err := s.sweepBlobs(ctx, &st); err != nil {
			return st, err
		}
		s.lastSweep = s.now()
	}
	return st, nil
}

func (s *Service) removeOrphan(ctx context.Context, id uuid.UUID, sum []byte) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := s.q.WithTx(tx).DeleteFileByID(ctx, id); err != nil {
		return err
	}
	if err := s.dropBlobIfUnused(ctx, tx, sum); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// sweepBlobs removes bytes on disk that no file points at (the owner was deleted along with their rows, or a crash came
// between two steps). Only bytes older than an hour are touched, so a file being finished is never in its way.
func (s *Service) sweepBlobs(ctx context.Context, st *CleanupStats) error {
	stale, err := s.store.OldBlobs(time.Hour)
	if err != nil {
		return err
	}
	for _, sum := range stale {
		tx, err := s.pool.Begin(ctx)
		if err != nil {
			return err
		}
		err = s.dropBlobIfUnused(ctx, tx, sum)
		if err == nil {
			err = tx.Commit(ctx)
		} else {
			_ = tx.Rollback(ctx)
		}
		if err != nil {
			return err
		}
		st.StrayBlobs++
	}
	return nil
}

// RunCleanup does a pass every `every` until ctx ends. The advisory lock lets exactly one replica work at a time; the
// others skip the turn.
func (s *Service) RunCleanup(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			s.cleanupOnce(ctx)
		}
	}
}

func (s *Service) cleanupOnce(ctx context.Context) {
	conn, err := s.pool.Acquire(ctx)
	if err != nil {
		return
	}
	defer conn.Release()
	var got bool
	if err := conn.QueryRow(ctx, "SELECT pg_try_advisory_lock($1)", advisoryKey).Scan(&got); err != nil || !got {
		return
	}
	defer func() { _, _ = conn.Exec(context.WithoutCancel(ctx), "SELECT pg_advisory_unlock($1)", advisoryKey) }()
	st, err := s.Cleanup(ctx)
	if err != nil {
		log.Printf("files clean-up: %v", err)
		return
	}
	if st != (CleanupStats{}) {
		log.Printf("files clean-up: %d expired uploads, %d orphans, %d stray dirs, %d stray tmp files, %d stray blobs", st.ExpiredUploads, st.Orphans, st.StrayDirs, st.StrayTmp, st.StrayBlobs)
	}
}
