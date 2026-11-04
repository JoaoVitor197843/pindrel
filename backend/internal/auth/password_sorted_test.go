package auth

import (
	"strings"
	"testing"
	"time"
)

func TestCommonPasswordsFileIsSortedTrimmedAndComplete(t *testing.T) {
	lines := strings.Split(strings.TrimSuffix(commonPasswordsRaw, "\n"), "\n")
	if !strings.HasSuffix(commonPasswordsRaw, "\n") || len(lines) < 90000 {
		t.Fatalf("file must end in a newline and keep its ~100k words, has %d lines", len(lines))
	}
	for i, l := range lines {
		if l == "" || l != strings.TrimSpace(l) {
			t.Fatalf("line %d %q is empty or has spaces around it", i+1, l)
		}
		if i > 0 && lines[i-1] >= l {
			t.Fatalf("line %d %q is not after %q: the file must be byte-sorted and without duplicates (LC_ALL=C sort -u)", i+1, l, lines[i-1])
		}
	}
}

func TestIsCommonPassword_FindsEveryWordAndNothingElse(t *testing.T) {
	lines := strings.Split(strings.TrimSuffix(commonPasswordsRaw, "\n"), "\n")
	for _, w := range lines {
		if !IsCommonPassword(w) {
			t.Fatalf("%q is in the list but was not found", w)
		}
		// a near miss must not match: prefix, extension, different case
		for _, miss := range []string{w + "x", w + "\n", "x" + w, w + " "} {
			if IsCommonPassword(miss) && !contains(lines, miss) {
				t.Fatalf("%q matched but is not in the list", miss)
			}
		}
	}
	for _, w := range []string{"", "\n", "\n\n", "zzzzzzzzzzzzzzzzzzzzz", "\x00", "ação-é-ü", strings.Repeat("a", 100000)} {
		if IsCommonPassword(w) && !contains(lines, w) {
			t.Fatalf("%q must not be common", w)
		}
	}
}

func TestInSortedLines_SmallEdges(t *testing.T) {
	raw := "a\nab\nb\n"
	for _, w := range []string{"a", "ab", "b"} {
		if !inSortedLines(raw, w) {
			t.Errorf("%q should be found", w)
		}
	}
	for _, w := range []string{"", "c", "0", "abc", "aa", "a\nab"} {
		if inSortedLines(raw, w) {
			t.Errorf("%q should not be found", w)
		}
	}
	if inSortedLines("", "a") {
		t.Error("empty list finds nothing")
	}
	if !inSortedLines("only\n", "only") || inSortedLines("only\n", "on") {
		t.Error("single line list")
	}
}

func TestIsCommonPassword_IsFastEnough(t *testing.T) {
	start := time.Now()
	const n = 20000
	for i := 0; i < n; i++ {
		IsCommonPassword("not-a-common-password-" + strings.Repeat("x", i%40))
	}
	if per := time.Since(start) / n; per > 100*time.Microsecond {
		t.Fatalf("a lookup took %v, expected microseconds", per)
	}
}

func contains(ss []string, s string) bool {
	for _, x := range ss {
		if x == s {
			return true
		}
	}
	return false
}
