package files

import (
	"archive/zip"
	"bytes"
	"strings"
	"testing"
)

// samples are the first bytes of real formats: enough for the detector, which is what the server relies on.
func sample(t *testing.T, kind string) []byte {
	t.Helper()
	pad := func(b []byte) []byte { return append(b, bytes.Repeat([]byte{0}, 64)...) }
	switch kind {
	case "png":
		return pad([]byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00"))
	case "jpeg":
		return pad([]byte("\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"))
	case "gif":
		return pad([]byte("GIF89a\x01\x00\x01\x00\x80\x00\x00"))
	case "webp":
		return pad([]byte("RIFF\x24\x00\x00\x00WEBPVP8 "))
	case "pdf":
		return pad([]byte("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n1 0 obj\n"))
	case "mp4":
		return pad([]byte("\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom"))
	case "webm":
		return pad([]byte("\x1a\x45\xdf\xa3\xa3\x42\x86\x81\x01\x42\xf7\x81\x01\x42\xf2\x81\x04\x42\xf3\x81\x08\x42\x82\x84webm\x42\x87\x81\x04\x42\x85\x81\x02"))
	case "mkv":
		return pad([]byte("\x1a\x45\xdf\xa3\xa3\x42\x86\x81\x01\x42\xf7\x81\x01\x42\xf2\x81\x04\x42\xf3\x81\x08\x42\x82\x88matroska\x42\x87\x81\x04\x42\x85\x81\x02"))
	case "mp3":
		return pad([]byte("ID3\x03\x00\x00\x00\x00\x00\x21"))
	case "ogg":
		return pad([]byte("OggS\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x01\x1eaudiovorbis"))
	case "wav":
		return pad([]byte("RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00"))
	case "html":
		return []byte("<!DOCTYPE html><html><head><script>alert(1)</script></head><body>oi</body></html>")
	case "svg":
		return []byte(`<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><circle r="5"/></svg>`)
	case "text":
		return []byte(strings.Repeat("uma linha de texto comum\n", 20))
	case "json":
		return []byte(`{"a": 1, "b": [1, 2, 3]}`)
	case "zip":
		return zipOf(t, map[string]string{"a.txt": "oi"})
	case "docx":
		return zipOf(t, map[string]string{"[Content_Types].xml": `<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>`, "_rels/.rels": "<x/>", "word/document.xml": "<w/>"})
	case "exe":
		return pad([]byte("MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00\xff\xff\x00\x00"))
	}
	t.Fatalf("unknown sample %q", kind)
	return nil
}

func zipOf(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	w := zip.NewWriter(&buf)
	// the order matters to the detector: Office puts the content types first
	for _, name := range []string{"[Content_Types].xml", "_rels/.rels", "word/document.xml", "a.txt"} {
		body, ok := files[name]
		if !ok {
			continue
		}
		f, err := w.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		_, _ = f.Write([]byte(body))
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}
