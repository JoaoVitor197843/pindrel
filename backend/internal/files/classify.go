package files

import (
	"mime"
	"strings"
	"unicode/utf8"

	"github.com/gabriel-vasile/mimetype"
)

// Level says how a file is handed out. The type is decided from the bytes (mimetype reads the start of the file), never
// from what the client says, and it only chooses how the file is delivered; it never declares a file safe.
type Level int16

const (
	// LevelMedia plays or shows inside the page: the exact types of a closed list, sent inline with their real type.
	LevelMedia Level = 1
	// LevelDocument only downloads: common documents, archives and text.
	LevelDocument Level = 2
	// LevelOther only downloads, after a warning: everything else, and anything that can carry script (SVG, HTML).
	LevelOther Level = 3
)

// detectLimit is how much of a file the detector reads. Office files keep some signatures a little in; a miss only moves
// a file to a level that downloads, so it never opens anything.
const detectLimit = 128 << 10

func init() { mimetype.SetLimit(detectLimit) }

// A closed list: only these are ever shown or played inside a page.
var mediaTypes = []string{
	"image/png", "image/jpeg", "image/webp", "image/gif",
	"video/mp4", "video/webm",
	"audio/mpeg", "audio/ogg", "video/ogg", "application/ogg", "audio/wav", "audio/x-wav", "audio/x-m4a", "audio/mp4",
	"application/pdf",
}

var documentTypes = []string{
	"application/zip", "application/x-7z-compressed", "application/x-tar", "application/gzip", "application/epub+zip",
	"application/json", "text/plain", "text/csv",
}

// documentPrefixes: Office and OpenDocument types come in dozens of variants that share a prefix.
var documentPrefixes = []string{
	"application/vnd.openxmlformats-officedocument.",
	"application/vnd.oasis.opendocument.",
	"application/msword", "application/vnd.ms-excel", "application/vnd.ms-powerpoint",
}

// neverInline are types a browser would run (script, styles, active documents): whatever the detector calls a file, if it
// is one of these it is never level 1 or 2 content shown in a page, only a download.
var neverInline = []string{"image/svg+xml", "text/html", "application/xhtml+xml", "text/xml", "application/xml", "text/javascript", "application/javascript"}

// LevelOf places a detected type. An empty or unknown type is level 3.
func LevelOf(detected string) Level {
	m, _, err := mime.ParseMediaType(detected)
	if err != nil {
		return LevelOther
	}
	m = strings.ToLower(m)
	for _, t := range neverInline {
		if m == t {
			return LevelOther
		}
	}
	for _, t := range mediaTypes {
		if m == t {
			return LevelMedia
		}
	}
	for _, t := range documentTypes {
		if m == t {
			return LevelDocument
		}
	}
	for _, p := range documentPrefixes {
		if strings.HasPrefix(m, p) {
			return LevelDocument
		}
	}
	return LevelOther
}

// Detect reads the start of a file on disk and returns its type and level.
func Detect(path string) (string, Level) {
	m, err := mimetype.DetectFile(path)
	if err != nil || m == nil {
		return "application/octet-stream", LevelOther
	}
	// the detector may add a charset to text types; the type itself is what matters
	base := strings.ToLower(strings.TrimSpace(strings.SplitN(m.String(), ";", 2)[0]))
	if base == "" {
		return "application/octet-stream", LevelOther
	}
	return base, LevelOf(base)
}

// cleanName makes a name fit to show and to put in a header: valid UTF-8, no control characters, no path, at most 255
// bytes. It is never used as a path on disk.
func cleanName(name string) string {
	if !utf8.ValidString(name) {
		name = strings.ToValidUTF8(name, "")
	}
	var b strings.Builder
	for _, r := range name {
		switch {
		case r < 0x20 || r == 0x7f || (r >= 0x80 && r < 0xa0):
			continue
		case r == '/' || r == '\\' || r == '‮' || r == '⁦' || r == '⁧' || r == '⁨' || r == '⁩':
			// separators, and the characters that make a name read backwards (a.exe shown as a.txt)
			b.WriteRune('_')
		default:
			b.WriteRune(r)
		}
	}
	out := strings.TrimSpace(b.String())
	for len(out) > 255 {
		_, size := utf8.DecodeLastRuneInString(out)
		out = out[:len(out)-size]
	}
	return strings.Trim(out, ". ")
}
