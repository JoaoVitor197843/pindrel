package clientip_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"plany/internal/clientip"
)

func resolver(t *testing.T, trusted, header string) *clientip.Resolver {
	t.Helper()
	nets, err := clientip.ParseTrusted(trusted)
	if err != nil {
		t.Fatalf("ParseTrusted(%q): %v", trusted, err)
	}
	r, err := clientip.New(nets, header)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return r
}

// req builds a request that came from `peer` carrying header lines (name, value, name, value...).
func req(peer string, lines ...string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = peer
	for i := 0; i+1 < len(lines); i += 2 {
		r.Header.Add(lines[i], lines[i+1])
	}
	return r
}

func TestWithoutTrustedProxiesTheHeadersAreNeverRead(t *testing.T) {
	r := resolver(t, "", "X-Forwarded-For")
	for _, peer := range []string{"203.0.113.5:4000", "127.0.0.1:4000", "[::1]:4000"} {
		got := r.Key(req(peer, "X-Forwarded-For", "9.9.9.9", "Cf-Connecting-Ip", "8.8.8.8"))
		if got != clientip.PeerKey(req(peer)) || got == "9.9.9.9" {
			t.Errorf("peer %s: key %q", peer, got)
		}
	}
}

// The library alone would believe this: its strategies ignore who connected.
func TestAnUntrustedPeerCannotSetItsOwnAddress(t *testing.T) {
	r := resolver(t, "127.0.0.1, 10.0.0.0/8", "X-Forwarded-For")
	if got := r.Key(req("203.0.113.5:4000", "X-Forwarded-For", "9.9.9.9")); got != "203.0.113.5" {
		t.Errorf("got %q", got)
	}
}

func TestATrustedProxyVouchesForTheClient(t *testing.T) {
	r := resolver(t, "127.0.0.1", "X-Forwarded-For")
	if got := r.Key(req("127.0.0.1:1", "X-Forwarded-For", "198.51.100.7")); got != "198.51.100.7" {
		t.Errorf("got %q", got)
	}
}

func TestWhatTheClientWroteOnTheLeftIsNeverUsed(t *testing.T) {
	r := resolver(t, "127.0.0.1", "X-Forwarded-For")
	if got := r.Key(req("127.0.0.1:1", "X-Forwarded-For", "9.9.9.9, 198.51.100.7")); got != "198.51.100.7" {
		t.Errorf("got %q", got)
	}
}

func TestTrustedProxiesInTheChainAreSkippedAndAnUntrustedHopStopsTheWalk(t *testing.T) {
	r := resolver(t, "127.0.0.1, 10.0.0.0/8", "X-Forwarded-For")
	if got := r.Key(req("127.0.0.1:1", "X-Forwarded-For", "9.9.9.9, 198.51.100.7, 10.1.2.3")); got != "198.51.100.7" {
		t.Errorf("skip: got %q", got)
	}
	if got := r.Key(req("127.0.0.1:1", "X-Forwarded-For", "1.1.1.1, 203.0.113.9, 10.1.2.3")); got != "203.0.113.9" {
		t.Errorf("stop: got %q", got)
	}
}

func TestSeveralHeaderLinesAreOneListInOrder(t *testing.T) {
	r := resolver(t, "127.0.0.1", "X-Forwarded-For")
	got := r.Key(req("127.0.0.1:1", "X-Forwarded-For", "9.9.9.9", "X-Forwarded-For", "198.51.100.7"))
	if got != "198.51.100.7" {
		t.Errorf("a client cannot hide behind a first line: got %q", got)
	}
}

func TestOnlyTheConfiguredHeaderCounts(t *testing.T) {
	r := resolver(t, "127.0.0.1", "X-Forwarded-For")
	lies := []string{"Forwarded", "for=9.9.9.9", "X-Real-Ip", "9.9.9.9", "Cf-Connecting-Ip", "9.9.9.9"}
	if got := r.Key(req("127.0.0.1:1", lies...)); got != "127.0.0.1" {
		t.Errorf("no X-Forwarded-For: the proxy is the client, got %q", got)
	}
	if got := r.Key(req("127.0.0.1:1", append(lies, "X-Forwarded-For", "198.51.100.7")...)); got != "198.51.100.7" {
		t.Errorf("a client-sent Forwarded must not win: got %q", got)
	}
}

func TestSingleAddressHeaderLikeCloudflares(t *testing.T) {
	r := resolver(t, "127.0.0.1", "cf-connecting-ip")
	cases := map[string][]string{
		"198.51.100.7": {"Cf-Connecting-Ip", "198.51.100.7"},
		"2001:db8::":   {"Cf-Connecting-Ip", "2001:db8::7"}, // an IPv6 client counts as its /64
		"127.0.0.1":    {"X-Forwarded-For", "9.9.9.9"},      // not the configured header
	}
	for want, lines := range cases {
		if got := r.Key(req("127.0.0.1:1", lines...)); got != want {
			t.Errorf("%v: got %q, want %q", lines, got, want)
		}
	}
	if got := r.Key(req("127.0.0.1:1", "Cf-Connecting-Ip", "not an ip")); got != "127.0.0.1" {
		t.Errorf("invalid value: got %q", got)
	}
}

func TestRFC7239Forwarded(t *testing.T) {
	r := resolver(t, "127.0.0.1", "Forwarded")
	if got := r.Key(req("127.0.0.1:1", "Forwarded", "for=9.9.9.9, for=198.51.100.7;proto=https")); got != "198.51.100.7" {
		t.Errorf("got %q", got)
	}
	if got := r.Key(req("127.0.0.1:1", "Forwarded", `for="[2001:db8::7]:4711"`)); got != "2001:db8::" {
		t.Errorf("ipv6 with port: got %q", got)
	}
}

func TestGarbageFallsBackToTheProxy(t *testing.T) {
	r := resolver(t, "127.0.0.1", "X-Forwarded-For")
	for _, bad := range []string{"", "   ", ",", "unknown", "9.9.9.9, _hidden", "999.1.1.1", "9.9.9.9;x", "[::1", "1.1.1.1/8"} {
		if got := r.Key(req("127.0.0.1:1", "X-Forwarded-For", bad)); got != "127.0.0.1" {
			t.Errorf("%q: got %q, want the proxy", bad, got)
		}
	}
}

func TestAnAbsurdlyLongHeaderIsIgnored(t *testing.T) {
	r := resolver(t, "127.0.0.1", "X-Forwarded-For")
	long := strings.Repeat("198.51.100.7, ", 300) + "198.51.100.8"
	if got := r.Key(req("127.0.0.1:1", "X-Forwarded-For", long)); got != "127.0.0.1" {
		t.Errorf("long header: got %q", got)
	}
	var lines []string
	for i := 0; i < 10; i++ {
		lines = append(lines, "X-Forwarded-For", strings.Repeat("198.51.100.7, ", 30))
	}
	if got := r.Key(req("127.0.0.1:1", lines...)); got != "127.0.0.1" {
		t.Errorf("many lines add up: got %q", got)
	}
}

func TestMappedIPv4AndIPv6Prefix(t *testing.T) {
	r := resolver(t, "127.0.0.1, fd7a:115c:a1e0::/48", "X-Forwarded-For")
	if got := r.Key(req("[::ffff:127.0.0.1]:1", "X-Forwarded-For", "::ffff:198.51.100.7")); got != "198.51.100.7" {
		t.Errorf("mapped: got %q", got)
	}
	a := r.Key(req("[fd7a:115c:a1e0::1]:1", "X-Forwarded-For", "2001:db8:1:2::1"))
	b := r.Key(req("[fd7a:115c:a1e0::1]:1", "X-Forwarded-For", "2001:db8:1:2:ffff::9"))
	c := r.Key(req("[fd7a:115c:a1e0::1]:1", "X-Forwarded-For", "2001:db8:1:3::1"))
	if a != b || a == c {
		t.Errorf("the same /64 must be one client and another /64 another: %q %q %q", a, b, c)
	}
	if got := r.Key(req("[fd7a:115c:a1f0::1]:1", "X-Forwarded-For", "9.9.9.9")); got == "9.9.9.9" {
		t.Errorf("outside the trusted range the header must be ignored")
	}
}

func TestPeerKeyIsTheConnectionsAddress(t *testing.T) {
	for peer, want := range map[string]string{
		"203.0.113.5:80":          "203.0.113.5",
		"[2001:db8:1:2::9]:80":    "2001:db8:1:2::",
		"[::ffff:203.0.113.5]:80": "203.0.113.5",
		"203.0.113.5":             "203.0.113.5", // no port
		"@":                       "@",           // not an address at all: counted as it is
	} {
		if got := clientip.PeerKey(req(peer)); got != want {
			t.Errorf("%q: got %q, want %q", peer, got, want)
		}
	}
}

func TestNilResolverIsThePeer(t *testing.T) {
	var r *clientip.Resolver
	if got := r.Key(req("203.0.113.5:80", "X-Forwarded-For", "9.9.9.9")); got != "203.0.113.5" {
		t.Errorf("got %q", got)
	}
}

func TestConfigParsing(t *testing.T) {
	if n, err := clientip.ParseTrusted(" 127.0.0.1 , ::1 ,10.0.0.0/8,"); err != nil || len(n) != 3 {
		t.Errorf("good list: %v %v", n, err)
	}
	for _, bad := range []string{"127.0.0.1, banana", "10.0.0.0/33", "fe80::1%eth0"} {
		if _, err := clientip.ParseTrusted(bad); err == nil {
			t.Errorf("%q must be rejected", bad)
		}
	}
	nets, _ := clientip.ParseTrusted("127.0.0.1")
	for _, bad := range []string{"bad header name", "", "Bad:Name"} {
		if _, err := clientip.New(nets, bad); err == nil {
			t.Errorf("header %q must be rejected", bad)
		}
	}
	if _, err := clientip.New(nil, "bad header name"); err == nil {
		t.Errorf("a bad header name is a configuration mistake even before any proxy is trusted")
	}
}

func TestNothingInTheInputMakesItPanic(t *testing.T) {
	odd := []string{"[", "]", "[::1", "::1]", "for=", "for=;", `for="`, ";;;", ",,,,", "a=b=c", "for=[", `for="[::1]:99999"`, "-1.1.1.1", "1.1.1.1.1", "\x00", "١.١.١.١"}
	for _, header := range []string{"X-Forwarded-For", "Forwarded", "Cf-Connecting-Ip"} {
		r := resolver(t, "127.0.0.1", header)
		for _, v := range odd {
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			req.RemoteAddr = "127.0.0.1:1"
			req.Header[header] = []string{v}
			_ = r.Key(req)
		}
		for _, peer := range []string{"", "x", "127.0.0.1", "[::1]", ":80", "127.0.0.1:"} {
			_ = r.Key(req0(peer))
		}
	}
}

func req0(peer string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = peer
	return r
}
