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

func TestStore_BlobPathCannotEscapeAndRemoveIsIdempotent(t *testing.T) {
	s := newStore(t)
	p := s.BlobPath(sum([]byte("x")))
	if !strings.HasPrefix(p, filepath.Join(s.dir, "blobs")+string(filepath.Separator)) || strings.Contains(p, "..") {
		t.Errorf("path %q", p)
	}
	if err := s.RemoveBlob(sum([]byte("nada"))); err != nil {
		t.Errorf("removing a missing blob: %v", err)
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
