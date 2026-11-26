package files

import (
	"bytes"
	"crypto/sha256"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/iotest"
	"time"

	"github.com/google/uuid"
)

func newStore(t *testing.T) *Store {
	t.Helper()
	s, err := NewStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func sum(b []byte) []byte { h := sha256.Sum256(b); return h[:] }

func TestStore_PiecesJoinInOrderWhateverTheArrivalOrder(t *testing.T) {
	s := newStore(t)
	id := uuid.New()
	data := bytes.Repeat([]byte("0123456789"), 1000) // 10000 bytes, pieces of 4096
	chunk := int64(4096)
	pieces := [][]byte{data[:4096], data[4096:8192], data[8192:]}
	for _, n := range []int{2, 0, 1} {
		if err := s.WritePiece(id, n, bytes.NewReader(pieces[n]), int64(len(pieces[n])), sum(pieces[n])); err != nil {
			t.Fatalf("piece %d: %v", n, err)
		}
	}
	path, got, err := s.Join(id, 3, chunk, int64(len(data)))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, sum(data)) {
		t.Error("hash of the joined file is wrong")
	}
	b, _ := os.ReadFile(path)
	if !bytes.Equal(b, data) {
		t.Error("joined bytes differ")
	}
}

func TestStore_PieceChecksLengthAndHashAndLeavesNothingBehind(t *testing.T) {
	s := newStore(t)
	id := uuid.New()
	piece := []byte("abcdefgh")
	for name, tc := range map[string]struct {
		body io.Reader
		want int64
		sum  []byte
		err  error
	}{
		"too short":  {bytes.NewReader(piece[:4]), 8, sum(piece), ErrBadChunkSize},
		"too long":   {bytes.NewReader(append(piece, 'x')), 8, sum(piece), ErrBadChunkSize},
		"wrong hash": {bytes.NewReader(piece), 8, sum([]byte("outra coisa")), ErrChunkHash},
		"empty":      {bytes.NewReader(nil), 8, sum(piece), ErrBadChunkSize},
		"huge body":  {io.LimitReader(zeros{}, 1<<30), 8, sum(piece), ErrBadChunkSize},
	} {
		if err := s.WritePiece(id, 0, tc.body, tc.want, tc.sum); !errors.Is(err, tc.err) {
			t.Errorf("%s: got %v, want %v", name, err, tc.err)
		}
	}
	if _, err := os.Stat(s.piecePath(id, 0)); err == nil {
		t.Error("a refused piece must not appear")
	}
	if left, _ := os.ReadDir(s.tmpDir()); len(left) != 0 {
		t.Errorf("temporary files left behind: %d", len(left))
	}
}

type zeros struct{}

func (zeros) Read(p []byte) (int, error) { clear(p); return len(p), nil }

func TestStore_ABrokenConnectionLeavesNoPiece(t *testing.T) {
	s := newStore(t)
	id := uuid.New()
	r := io.MultiReader(strings.NewReader("abcd"), iotest.ErrReader(errors.New("connection reset")))
	if err := s.WritePiece(id, 0, r, 8, sum([]byte("abcdefgh"))); err == nil {
		t.Fatal("a cut body must fail")
	}
	if _, err := os.Stat(s.piecePath(id, 0)); err == nil {
		t.Error("a half piece must not be trusted by a later join")
	}
}

func TestStore_JoinRefusesMissingOrDamagedPieces(t *testing.T) {
	s := newStore(t)
	id := uuid.New()
	a, b := []byte("aaaa"), []byte("bb")
	if err := s.WritePiece(id, 0, bytes.NewReader(a), 4, sum(a)); err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.Join(id, 2, 4, 6); !errors.Is(err, ErrIncomplete) {
		t.Errorf("missing piece: %v", err)
	}
	if err := s.WritePiece(id, 1, bytes.NewReader(b), 2, sum(b)); err != nil {
		t.Fatal(err)
	}
	// a piece truncated or swapped on disk after it was accepted
	if err := os.WriteFile(s.piecePath(id, 1), []byte("b"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.Join(id, 2, 4, 6); !errors.Is(err, ErrIncomplete) {
		t.Errorf("damaged piece: %v", err)
	}
	if left, _ := os.ReadDir(s.tmpDir()); len(left) != 0 {
		t.Errorf("a failed join left %d temporary files", len(left))
	}
}

func TestStore_EqualContentTakesTheSpaceOnce(t *testing.T) {
	s := newStore(t)
	data := []byte("o mesmo conteúdo")
	for i := 0; i < 3; i++ {
		id := uuid.New()
		if err := s.WritePiece(id, 0, bytes.NewReader(data), int64(len(data)), sum(data)); err != nil {
			t.Fatal(err)
		}
		path, h, err := s.Join(id, 1, int64(len(data)), int64(len(data)))
		if err != nil {
			t.Fatal(err)
		}
		if err := s.Commit(path, h); err != nil {
			t.Fatal(err)
		}
	}
	count := 0
	_ = filepath.WalkDir(filepath.Join(s.dir, "blobs"), func(_ string, d os.DirEntry, _ error) error {
		if !d.IsDir() {
			count++
		}
		return nil
	})
	if count != 1 {
		t.Errorf("%d blobs for equal content, want 1", count)
	}
}

func TestStore_BlobPathCannotEscape(t *testing.T) {
	s := newStore(t)
	p := s.BlobPath(sum([]byte("x")))
	if !strings.HasPrefix(p, filepath.Join(s.dir, "blobs")+string(filepath.Separator)) || strings.Contains(p, "..") {
		t.Errorf("path %q", p)
	}
}

// storeBlob puts a finished file with this content in place, as Join + Commit would.
func storeBlob(t *testing.T, s *Store, data []byte) []byte {
	t.Helper()
	tmp := filepath.Join(s.tmpDir(), "x-"+uuid.NewString())
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := s.Commit(tmp, sum(data)); err != nil {
		t.Fatal(err)
	}
	return sum(data)
}

// The bytes of a deleted file are only moved aside inside the transaction: a commit that fails puts them back, so the file
// row the rollback keeps still has its bytes.
func TestStore_ReleaseThenRestoreOrDiscard(t *testing.T) {
	s := newStore(t)
	if aside, err := s.Release(sum([]byte("nada"))); err != nil || aside != "" {
		t.Fatalf("releasing a missing blob: %q %v", aside, err)
	}

	data := []byte("conteúdo")
	h := storeBlob(t, s, data)
	aside, err := s.Release(h)
	if err != nil || aside == "" {
		t.Fatalf("release: %q %v", aside, err)
	}
	if _, err := os.Stat(s.BlobPath(h)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("the bytes are still in place after the release")
	}
	s.Restore(aside, h)
	if got, err := os.ReadFile(s.BlobPath(h)); err != nil || !bytes.Equal(got, data) {
		t.Fatalf("restore: %q %v", got, err)
	}

	aside, _ = s.Release(h)
	s.Discard(aside)
	s.Discard(aside) // twice: a retry must not fail
	if _, err := os.Stat(aside); !errors.Is(err, os.ErrNotExist) {
		t.Error("discard left the released bytes")
	}
	if _, err := os.Stat(s.BlobPath(h)); !errors.Is(err, os.ErrNotExist) {
		t.Error("discard brought the bytes back")
	}
}

// While a failed transaction was releasing them, a new file with the same content put its own bytes in place: they are the
// same bytes (the name is the hash), so the released copy is dropped and the new one stays.
func TestStore_RestoreWhenTheContentCameBackMeanwhile(t *testing.T) {
	s := newStore(t)
	data := []byte("mesmo conteúdo")
	h := storeBlob(t, s, data)
	aside, _ := s.Release(h)
	storeBlob(t, s, data)
	s.Restore(aside, h)
	if _, err := os.Stat(aside); !errors.Is(err, os.ErrNotExist) {
		t.Error("the released copy was kept next to the new one")
	}
	if got, _ := os.ReadFile(s.BlobPath(h)); !bytes.Equal(got, data) {
		t.Error("the bytes in place are damaged")
	}
}

func TestStore_StraysAreOnlyTheOldOnes(t *testing.T) {
	s := newStore(t)
	old, fresh := uuid.New(), uuid.New()
	for _, id := range []uuid.UUID{old, fresh} {
		if err := os.MkdirAll(s.uploadDir(id), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	past := time.Now().Add(-48 * time.Hour)
	_ = os.Chtimes(s.uploadDir(old), past, past)
	oldTmp := filepath.Join(s.tmpDir(), "join-old")
	_ = os.WriteFile(oldTmp, []byte("x"), 0o600)
	_ = os.Chtimes(oldTmp, past, past)
	_ = os.WriteFile(filepath.Join(s.tmpDir(), "join-new"), []byte("x"), 0o600)
	_ = os.MkdirAll(filepath.Join(s.dir, "uploads", "not-a-uuid"), 0o700)
	dirs, tmps, err := s.StrayUploadDirs(24 * time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if len(dirs) != 1 || dirs[0] != old || len(tmps) != 1 || tmps[0] != oldTmp {
		t.Errorf("strays: %v %v", dirs, tmps)
	}
}

func TestAllReceived(t *testing.T) {
	if !allReceived([]byte{0b0000_0111}, 3) || allReceived([]byte{0b0000_0101}, 3) || allReceived([]byte{0xff}, 9) || !allReceived([]byte{0xff, 0x01}, 9) || allReceived(nil, 1) {
		t.Error("bitmap check is wrong")
	}
}
