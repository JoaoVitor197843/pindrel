package files

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func detect(t *testing.T, data []byte) (string, Level) {
	t.Helper()
	p := filepath.Join(t.TempDir(), "f")
	if err := os.WriteFile(p, data, 0o600); err != nil {
		t.Fatal(err)
	}
	return Detect(p)
}

func TestDetect_EachKindLandsOnItsLevel(t *testing.T) {
	cases := []struct {
		kind  string
		level Level
	}{
		{"png", LevelMedia}, {"jpeg", LevelMedia}, {"gif", LevelMedia}, {"webp", LevelMedia}, {"pdf", LevelMedia},
		{"mp4", LevelMedia}, {"mp3", LevelMedia}, {"ogg", LevelMedia}, {"wav", LevelMedia},
		{"text", LevelDocument}, {"json", LevelDocument}, {"zip", LevelDocument}, {"docx", LevelDocument},
		{"html", LevelOther}, {"svg", LevelOther}, {"exe", LevelOther},
	}
	for _, c := range cases {
		mt, level := detect(t, sample(t, c.kind))
		if level != c.level {
			t.Errorf("%s: detected %q at level %d, want level %d", c.kind, mt, level, c.level)
		}
	}
}

func TestDetect_WebMIsMedia(t *testing.T) {
	// the detector's name for the EBML container varies; the level is what the server relies on
	if mt, level := detect(t, sample(t, "webm")); level != LevelMedia {
		t.Errorf("webm: %q at level %d", mt, level)
	}
}

func TestDetect_MatroskaIsNotWebM(t *testing.T) {
	// a .mkv can hold anything a browser will not play; it only downloads
	if mt, level := detect(t, sample(t, "mkv")); level == LevelMedia {
		t.Errorf("mkv: %q at level %d", mt, level)
	}
}

func TestDetect_ContentWinsOverTheNameAndHtmlIsNeverMedia(t *testing.T) {
	// the server never sees the name here, only the bytes: an HTML file called x.png is still HTML
	mt, level := detect(t, sample(t, "html"))
	if level != LevelOther || !strings.HasPrefix(mt, "text/html") {
		t.Errorf("html: %q level %d", mt, level)
	}
	// a program with the header of a picture is a picture to the detector, but it is delivered as media only if the
	// whole detection says so; a program is never media
	if _, level := detect(t, sample(t, "exe")); level == LevelMedia {
		t.Error("an executable must not be media")
	}
}

func TestLevelOf_ClosedListAndSafeDefaults(t *testing.T) {
	for in, want := range map[string]Level{
		"image/png":                 LevelMedia,
		"IMAGE/PNG":                 LevelMedia,
		"image/png; charset=binary": LevelMedia,
		"image/svg+xml":             LevelOther,
		"text/html":                 LevelOther,
		"application/xhtml+xml":     LevelOther,
		"text/xml":                  LevelOther,
		"application/javascript":    LevelOther,
		"application/vnd.openxmlformats-officedocument.wordprocessingml.document": LevelDocument,
		"application/vnd.oasis.opendocument.text":                                 LevelDocument,
		"application/zip":          LevelDocument,
		"application/x-msdownload": LevelOther,
		"":                         LevelOther,
		"not a type":               LevelOther,
		"image/x-unknown":          LevelOther,
	} {
		if got := LevelOf(in); got != want {
			t.Errorf("LevelOf(%q) = %d, want %d", in, got, want)
		}
	}
}

func TestDetect_EmptyAndMissingFilesAreTheSafestLevel(t *testing.T) {
	if _, level := detect(t, nil); level == LevelMedia {
		t.Error("an empty file must not be media")
	}
	if mt, level := Detect(filepath.Join(t.TempDir(), "nope")); level != LevelOther || mt != "application/octet-stream" {
		t.Errorf("missing file: %q level %d", mt, level)
	}
}

func TestCleanName(t *testing.T) {
	for in, want := range map[string]string{
		"relatório final.pdf": "relatório final.pdf",
		"../../etc/passwd":    "_.._etc_passwd",
		`a\b/c`:               "a_b_c",
		"  espaços  ":         "espaços",
		"nul\x00byte\x1f.txt": "nulbyte.txt",
		"fdp‮gnp.exe":         "fdp_gnp.exe",
		"...":                 "",
		"":                    "",
		"\xff\xfe quebrado":   "quebrado",
		"linha\nnova\r.txt":   "linhanova.txt",
	} {
		if got := cleanName(in); got != want {
			t.Errorf("cleanName(%q) = %q, want %q", in, got, want)
		}
	}
	long := strings.Repeat("é", 400)
	if got := cleanName(long); len(got) > 255 || !strings.HasPrefix(long, got) {
		t.Errorf("long name: %d bytes", len(got))
	}
}
