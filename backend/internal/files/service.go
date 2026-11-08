// Package files stores the files of a note on the server's disk: sent in pieces, joined in a stream, handed out with
// plain HTTP Range requests through a signed address. No file ever sits whole in memory.
package files

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math/bits"
	"os"
	"time"

	"pindrel/internal/database/db"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ChunkSize is the size of every piece but the last. It must stay under the gateway's MAX_BODY_BYTES (1 MiB), which holds
// a whole request in memory before passing it on.
const ChunkSize = 512 << 10

var (
	ErrInvalidInput  = errors.New("invalid input")
	ErrTooLarge      = errors.New("file too large")
	ErrQuota         = errors.New("quota exceeded")
	ErrDiskFull      = errors.New("not enough free space on the server")
	ErrTooMany       = errors.New("too many uploads open")
	ErrUploadMissing = errors.New("upload not found")
	ErrUploadBusy    = errors.New("upload is being finished")
	ErrChunkRange    = errors.New("piece number out of range")
	ErrBadChunkSize  = errors.New("piece has the wrong size")
	ErrChunkHash     = errors.New("piece does not match its hash")
	ErrIncomplete    = errors.New("some pieces are missing")
	ErrFileMissing   = errors.New("file not found")
	ErrBadLink       = errors.New("download address is not valid")
)

// Config holds the limits. Every number is a setting of the server (see config.Config).
type Config struct {
	Dir            string
	MaxFileBytes   int64
	QuotaBytes     int64
	MinFreeBytes   int64
	MaxOpenUploads int
	UploadTTL      time.Duration
	OrphanGrace    time.Duration
	LinkTTL        time.Duration
	// Secret signs download addresses (the JWT secret, shared by every replica).
	Secret []byte
}

// Access decides who may read a file. Today only its owner can; when pages can be shared on the server, whoever a shared
// page lets in is added here and nowhere else.
type Access interface {
	CanView(ctx context.Context, viewer uuid.UUID, f db.File) (bool, error)
}

type ownerOnly struct{}

func (ownerOnly) CanView(_ context.Context, viewer uuid.UUID, f db.File) (bool, error) {
	return f.UserID == viewer, nil
}

type Service struct {
	q      *db.Queries
	pool   *pgxpool.Pool
	store  *Store
	cfg    Config
	access Access
	now    func() time.Time
	// lastSweep is when this replica last looked for bytes that no file uses.
	lastSweep time.Time
}

func NewService(pool *pgxpool.Pool, q *db.Queries, store *Store, cfg Config) *Service {
	return &Service{q: q, pool: pool, store: store, cfg: cfg, access: ownerOnly{}, now: time.Now}
}

// SetAccess swaps the rule of who may read a file (used once pages can be shared on the server).
func (s *Service) SetAccess(a Access) { s.access = a }

func chunkCount(size int64) int32 { return int32((size + ChunkSize - 1) / ChunkSize) }

func ts(t time.Time) pgtype.Timestamptz { return pgtype.Timestamptz{Time: t, Valid: true} }

// CreateUpload opens an upload after the checks that must not race: quota, number of open uploads and free disk, done with
// the user's row locked so two uploads started together cannot both pass.
func (s *Service) CreateUpload(ctx context.Context, user uuid.UUID, size int64, name string, encrypted bool) (db.Upload, error) {
	if size <= 0 {
		return db.Upload{}, ErrInvalidInput
	}
	if size > s.cfg.MaxFileBytes {
		return db.Upload{}, ErrTooLarge
	}
	if free, err := freeBytes(s.store.dir); err == nil && int64(min(free, 1<<62)) < s.cfg.MinFreeBytes+size {
		return db.Upload{}, ErrDiskFull
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return db.Upload{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	q := s.q.WithTx(tx)
	if err := q.LockUser(ctx, user); err != nil {
		return db.Upload{}, err
	}
	open, err := q.CountOpenUploads(ctx, user)
	if err != nil {
		return db.Upload{}, err
	}
	if int(open) >= s.cfg.MaxOpenUploads {
		return db.Upload{}, ErrTooMany
	}
	used, err := q.QuotaUsed(ctx, user)
	if err != nil {
		return db.Upload{}, err
	}
	if used+size > s.cfg.QuotaBytes {
		return db.Upload{}, ErrQuota
	}
	up, err := q.CreateUpload(ctx, db.CreateUploadParams{
		UserID:     user,
		Size:       size,
		ChunkSize:  ChunkSize,
		ChunkCount: chunkCount(size),
		Name:       cleanName(name),
		Encrypted:  encrypted,
		ExpiresAt:  ts(s.now().Add(s.cfg.UploadTTL)),
	})
	if err != nil {
		return db.Upload{}, err
	}
	return up, tx.Commit(ctx)
}

func (s *Service) Upload(ctx context.Context, user, id uuid.UUID) (db.Upload, error) {
	up, err := s.q.GetUpload(ctx, db.GetUploadParams{ID: id, UserID: user})
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && up.ExpiresAt.Time.Before(s.now())) {
		return db.Upload{}, ErrUploadMissing
	}
	return up, err
}

// PutChunk stores piece n. Sending the same piece again changes nothing (a retry after a lost answer is safe).
func (s *Service) PutChunk(ctx context.Context, user, id uuid.UUID, n int, body io.Reader, sum []byte) error {
	up, err := s.Upload(ctx, user, id)
	if err != nil {
		return err
	}
	if up.State != "open" {
		return ErrUploadBusy
	}
	if n < 0 || n >= int(up.ChunkCount) {
		return ErrChunkRange
	}
	if len(sum) != 32 {
		return ErrInvalidInput
	}
	want := int64(up.ChunkSize)
	if n == int(up.ChunkCount)-1 {
		want = up.Size - int64(up.ChunkSize)*int64(up.ChunkCount-1)
	}
	if err := s.store.WritePiece(id, n, body, want, sum); err != nil {
		return err
	}
	// the TTL runs from the last sign of life, so a long upload on a slow line is not cut off
	_, err = s.q.MarkChunkReceived(ctx, db.MarkChunkReceivedParams{ID: id, UserID: user, Column3: int32(n), ExpiresAt: ts(s.now().Add(s.cfg.UploadTTL))})
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrUploadBusy
	}
	return err
}

func allReceived(bitmap []byte, count int) bool {
	if len(bitmap)*8 < count {
		return false
	}
	ones := 0
	for _, b := range bitmap {
		ones += bits.OnesCount8(b)
	}
	// every bit set for pieces 0..count-1 (the rest of the last byte stays 0)
	return ones == count
}

// Finish joins the pieces, looks at the bytes to decide the type, and turns the upload into a file. Exactly one request
// can finish an upload; the join runs in a stream and holds no database connection while it works.
func (s *Service) Finish(ctx context.Context, user, id uuid.UUID) (db.File, error) {
	up, err := s.q.ClaimUploadForFinish(ctx, db.ClaimUploadForFinishParams{ID: id, UserID: user})
	if errors.Is(err, pgx.ErrNoRows) {
		if _, gerr := s.Upload(ctx, user, id); gerr == nil {
			return db.File{}, ErrUploadBusy
		}
		return db.File{}, ErrUploadMissing
	}
	if err != nil {
		return db.File{}, err
	}
	reopen := func() {
		// a failed finish gives the upload back, so the client can send what is missing and try again
		_ = s.q.ReopenUpload(context.WithoutCancel(ctx), db.ReopenUploadParams{ID: id, UserID: user, ExpiresAt: ts(s.now().Add(s.cfg.UploadTTL))})
	}
	if !allReceived(up.Received, int(up.ChunkCount)) {
		reopen()
		return db.File{}, ErrIncomplete
	}
	tmp, sum, err := s.store.Join(id, int(up.ChunkCount), int64(up.ChunkSize), up.Size)
	if err != nil {
		reopen()
		return db.File{}, err
	}
	mimeType, level := "application/octet-stream", LevelOther
	if !up.Encrypted {
		mimeType, level = Detect(tmp)
	}
	file, err := s.record(ctx, id, up, tmp, sum, mimeType, level)
	if err != nil {
		// the connection of the failed attempt is back in the pool by now, so giving the upload back never waits for one
		_ = os.Remove(tmp)
		reopen()
		return db.File{}, err
	}
	_ = s.store.RemoveUpload(id)
	return file, nil
}

// record puts the joined bytes in place and turns the upload into a file, in one transaction. Putting the bytes in place
// and recording the file happen under the lock of this content, so a delete of the last file with the same content cannot
// take the bytes away in between.
func (s *Service) record(ctx context.Context, id uuid.UUID, up db.Upload, tmp string, sum []byte, mimeType string, level Level) (db.File, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return db.File{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := lockHash(ctx, tx, sum); err != nil {
		return db.File{}, err
	}
	if err := s.store.Commit(tmp, sum); err != nil {
		return db.File{}, err
	}
	q := s.q.WithTx(tx)
	file, err := q.CreateFile(ctx, db.CreateFileParams{UserID: up.UserID, Sha256: sum, Size: up.Size, Mime: mimeType, Level: int16(level), Name: up.Name, Encrypted: up.Encrypted})
	if err != nil {
		return db.File{}, err
	}
	if err := q.DeleteUploadByID(ctx, id); err != nil {
		return db.File{}, err
	}
	return file, tx.Commit(ctx)
}

// Cancel drops an upload and its pieces.
func (s *Service) Cancel(ctx context.Context, user, id uuid.UUID) error {
	if _, err := s.q.DeleteUpload(ctx, db.DeleteUploadParams{ID: id, UserID: user}); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrUploadMissing
		}
		return err
	}
	return s.store.RemoveUpload(id)
}

// File returns a file the viewer may read.
func (s *Service) File(ctx context.Context, viewer, id uuid.UUID) (db.File, error) {
	f, err := s.q.GetFile(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return db.File{}, ErrFileMissing
	}
	if err != nil {
		return db.File{}, err
	}
	ok, err := s.access.CanView(ctx, viewer, f)
	if err != nil {
		return db.File{}, err
	}
	if !ok {
		// the same answer as a file that does not exist: no way to probe for other people's files
		return db.File{}, ErrFileMissing
	}
	return f, nil
}

// Link makes a short-lived download address for a file the viewer may read. It returns the path and when it expires.
func (s *Service) Link(ctx context.Context, viewer, id uuid.UUID) (string, time.Time, error) {
	if _, err := s.File(ctx, viewer, id); err != nil {
		return "", time.Time{}, err
	}
	until := s.now().Add(s.cfg.LinkTTL)
	exp, sig := SignLink(s.cfg.Secret, id, until)
	return fmt.Sprintf("/files/%s?exp=%d&sig=%s", id, exp, sig), until, nil
}

// Open checks a download address and opens the file it names.
func (s *Service) Open(ctx context.Context, id uuid.UUID, exp int64, sig string) (*os.File, db.File, error) {
	if !VerifyLink(s.cfg.Secret, id, exp, sig, s.now()) {
		return nil, db.File{}, ErrBadLink
	}
	f, err := s.q.GetFile(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, db.File{}, ErrFileMissing
	}
	if err != nil {
		return nil, db.File{}, err
	}
	fd, err := s.store.Open(f.Sha256)
	if err != nil {
		return nil, db.File{}, ErrFileMissing
	}
	return fd, f, nil
}

// Delete removes a file of the user, and its bytes when no other file uses the same content.
func (s *Service) Delete(ctx context.Context, user, id uuid.UUID) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	sum, err := s.q.WithTx(tx).DeleteFile(ctx, db.DeleteFileParams{ID: id, UserID: user})
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrFileMissing
	}
	if err != nil {
		return err
	}
	if err := s.dropBlobIfUnused(ctx, tx, sum); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// lockHash serialises everything that decides whether the bytes of one content exist: it is held until the transaction
// ends. The key is the start of the hash, so two contents only ever wait for each other by rare coincidence.
func lockHash(ctx context.Context, tx pgx.Tx, sum []byte) error {
	_, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock($1)", int64(binary.BigEndian.Uint64(sum[:8])))
	return err
}

// dropBlobIfUnused removes the bytes of a content when no file uses it any more. It runs inside the transaction that just
// removed a file, under the lock of that content.
func (s *Service) dropBlobIfUnused(ctx context.Context, tx pgx.Tx, sum []byte) error {
	if err := lockHash(ctx, tx, sum); err != nil {
		return err
	}
	n, err := s.q.WithTx(tx).CountFilesWithHash(ctx, sum)
	if err != nil || n > 0 {
		return err
	}
	return s.store.RemoveBlob(sum)
}

// MarkOrphan tells the server nothing uses a file any more (the page that held it was deleted, or the block removed). The
// clean-up removes it after the grace period unless the file is claimed again.
func (s *Service) MarkOrphan(ctx context.Context, user, id uuid.UUID, orphan bool) error {
	if _, err := s.q.GetFile(ctx, id); errors.Is(err, pgx.ErrNoRows) {
		return ErrFileMissing
	}
	if orphan {
		return s.q.MarkFileOrphan(ctx, db.MarkFileOrphanParams{ID: id, UserID: user})
	}
	return s.q.ClearFileOrphan(ctx, db.ClearFileOrphanParams{ID: id, UserID: user})
}

// List returns a page of the user's files, newest first, and the bytes used against the quota.
func (s *Service) List(ctx context.Context, user uuid.UUID, after time.Time, afterID uuid.UUID, limit int32) ([]db.File, int64, error) {
	rows, err := s.q.ListFiles(ctx, db.ListFilesParams{UserID: user, Column2: ts(after), Column3: afterID, Limit: limit})
	if err != nil {
		return nil, 0, err
	}
	used, err := s.q.QuotaUsed(ctx, user)
	return rows, used, err
}

// Quota is the limit per user.
func (s *Service) Quota() int64 { return s.cfg.QuotaBytes }
