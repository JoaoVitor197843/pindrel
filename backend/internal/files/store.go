package files

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/google/uuid"
)

// Store is the disk side. Nothing in it keeps a file in memory: bytes move through a fixed buffer.
//
//	<dir>/blobs/ab/cd/<sha256 hex>    a finished file, named by its content (equal files take the space once)
//	<dir>/uploads/<upload id>/<n>     the pieces of an upload in progress
//	<dir>/tmp/<random>                a file being joined or a piece being written, renamed when complete
type Store struct {
	dir string
}

func NewStore(dir string) (*Store, error) {
	s := &Store{dir: dir}
	for _, d := range []string{"blobs", "uploads", "tmp"} {
		if err := os.MkdirAll(filepath.Join(dir, d), 0o700); err != nil {
			return nil, fmt.Errorf("files directory %q: %w", dir, err)
		}
	}
	return s, nil
}

func (s *Store) tmpDir() string { return filepath.Join(s.dir, "tmp") }

func (s *Store) uploadDir(id uuid.UUID) string { return filepath.Join(s.dir, "uploads", id.String()) }

func (s *Store) piecePath(id uuid.UUID, n int) string {
	return filepath.Join(s.uploadDir(id), fmt.Sprintf("%06d", n))
}

// BlobPath is where a file with this content lives. The name is the hex of a hash, so no input can shape the path.
func (s *Store) BlobPath(sum []byte) string {
	h := hex.EncodeToString(sum)
	return filepath.Join(s.dir, "blobs", h[:2], h[2:4], h)
}

// WritePiece stores one piece, checking its length and hash while it streams to disk. The piece appears under its final
// name only when complete, so a cut connection leaves nothing a later join could trust.
func (s *Store) WritePiece(id uuid.UUID, n int, r io.Reader, want int64, wantSum []byte) error {
	if err := os.MkdirAll(s.uploadDir(id), 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(s.tmpDir(), "piece-*")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(tmp.Name()) }()
	h := sha256.New()
	// one byte more than expected, to tell "exactly right" from "too long" without reading the rest of a huge body
	written, err := io.Copy(io.MultiWriter(tmp, h), io.LimitReader(r, want+1))
	if err != nil {
		_ = tmp.Close()
		return err
	}
	if written != want {
		_ = tmp.Close()
		return ErrBadChunkSize
	}
	if !equalSum(h.Sum(nil), wantSum) {
		_ = tmp.Close()
		return ErrChunkHash
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), s.piecePath(id, n))
}

func equalSum(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var d byte
	for i := range a {
		d |= a[i] ^ b[i]
	}
	return d == 0
}

// Join concatenates the pieces, in order, into one file in tmp, hashing as it goes. Memory stays one 32 KiB buffer, however
// large the file. It returns the temporary path and the SHA-256 of the whole.
func (s *Store) Join(id uuid.UUID, count int, chunk int64, total int64) (string, []byte, error) {
	out, err := os.CreateTemp(s.tmpDir(), "join-*")
	if err != nil {
		return "", nil, err
	}
	path := out.Name()
	fail := func(err error) (string, []byte, error) {
		_ = out.Close()
		_ = os.Remove(path)
		return "", nil, err
	}
	h := sha256.New()
	w := io.MultiWriter(out, h)
	buf := make([]byte, 32<<10)
	var sum int64
	for n := 0; n < count; n++ {
		want := chunk
		if n == count-1 {
			want = total - chunk*int64(count-1)
		}
		f, err := os.Open(s.piecePath(id, n))
		if err != nil {
			return fail(fmt.Errorf("piece %d: %w", n, ErrIncomplete))
		}
		// the length is checked against what the upload promised, so a damaged or swapped piece cannot slip in
		st, err := f.Stat()
		if err != nil || st.Size() != want {
			_ = f.Close()
			return fail(fmt.Errorf("piece %d: %w", n, ErrIncomplete))
		}
		c, err := io.CopyBuffer(w, io.LimitReader(f, want), buf)
		_ = f.Close()
		if err != nil {
			return fail(err)
		}
		sum += c
	}
	if sum != total {
		return fail(ErrIncomplete)
	}
	if err := out.Sync(); err != nil {
		return fail(err)
	}
	if err := out.Close(); err != nil {
		_ = os.Remove(path)
		return "", nil, err
	}
	return path, h.Sum(nil), nil
}

// Commit moves a joined file to its final name. When a file with this content already exists, the new one is dropped and
// the old one serves both.
func (s *Store) Commit(tmpPath string, sum []byte) error {
	final := s.BlobPath(sum)
	if _, err := os.Stat(final); err == nil {
		return os.Remove(tmpPath)
	}
	if err := os.MkdirAll(filepath.Dir(final), 0o700); err != nil {
		return err
	}
	return os.Rename(tmpPath, final)
}

func (s *Store) Open(sum []byte) (*os.File, error) { return os.Open(s.BlobPath(sum)) }

func (s *Store) RemoveBlob(sum []byte) error {
	err := os.Remove(s.BlobPath(sum))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

// OldBlobs lists the content hashes of files on disk last written more than `age` ago.
func (s *Store) OldBlobs(age time.Duration) ([][]byte, error) {
	cut := time.Now().Add(-age)
	var out [][]byte
	err := filepath.WalkDir(filepath.Join(s.dir, "blobs"), func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		sum, derr := hex.DecodeString(d.Name())
		info, ierr := d.Info()
		if derr == nil && len(sum) == sha256.Size && ierr == nil && info.ModTime().Before(cut) {
			out = append(out, sum)
		}
		return nil
	})
	return out, err
}

func (s *Store) RemoveUpload(id uuid.UUID) error { return os.RemoveAll(s.uploadDir(id)) }

// StrayUploadDirs lists upload directories older than `age` whose id the caller can check against the database, and
// temporary files older than `age` (a crash in the middle of a join or a piece leaves one).
func (s *Store) StrayUploadDirs(age time.Duration) (dirs []uuid.UUID, tmpFiles []string, err error) {
	cut := time.Now().Add(-age)
	entries, err := os.ReadDir(filepath.Join(s.dir, "uploads"))
	if err != nil {
		return nil, nil, err
	}
	for _, e := range entries {
		id, perr := uuid.Parse(e.Name())
		info, ierr := e.Info()
		if perr != nil || ierr != nil || !e.IsDir() || info.ModTime().After(cut) {
			continue
		}
		dirs = append(dirs, id)
	}
	tmps, err := os.ReadDir(s.tmpDir())
	if err != nil {
		return dirs, nil, err
	}
	for _, e := range tmps {
		if info, ierr := e.Info(); ierr == nil && !info.IsDir() && info.ModTime().Before(cut) {
			tmpFiles = append(tmpFiles, filepath.Join(s.tmpDir(), e.Name()))
		}
	}
	return dirs, tmpFiles, nil
}
