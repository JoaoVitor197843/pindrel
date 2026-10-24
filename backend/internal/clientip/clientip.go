// Package clientip decides which address a request comes from, for the per-client rate limits of a single
// instance running without the gateway.
//
// Anything a client can write is a lie, so nothing a client sends is believed unless the connection came from a
// proxy the operator declared (TRUSTED_PROXIES). Then only the one header named by CLIENT_IP_HEADER is read, from
// the right: realclientip-go skips the trusted proxies and answers with the first address that is not one.
// Same rules, names and defaults as gateway/src/clientip.rs.
//
// The library does NOT check who connected (its strategies ignore the remote address): a direct client could send
// "X-Forwarded-For: anything" and the rightmost untrusted entry would be what it wrote. That check is Resolver.Key's.
package clientip

import (
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"strings"

	"github.com/realclientip/realclientip-go"
)

// maxHeaderLen is longer than any honest chain of proxies: a longer header is ignored (the library parses every
// entry before choosing one, so this also bounds the work an attacker can make us do).
const maxHeaderLen = 2048

// Resolver turns a request into the key its rate limits are counted under.
type Resolver struct {
	trusted  []net.IPNet
	header   string
	strategy realclientip.Strategy
}

// ParseTrusted reads a comma-separated list of addresses and CIDR ranges ("127.0.0.1, ::1, 10.0.0.0/8").
func ParseTrusted(spec string) ([]net.IPNet, error) {
	var items []string
	for _, s := range strings.Split(spec, ",") {
		if s = strings.TrimSpace(s); s != "" {
			items = append(items, s)
		}
	}
	if len(items) == 0 {
		return nil, nil
	}
	return realclientip.AddressesAndRangesToIPNets(items...)
}

// New builds a Resolver. With no trusted proxies every request is its own connection's address and the header is
// never read. header is "X-Forwarded-For" (a list), "Forwarded" (RFC 7239) or the name of a single-address header
// such as "CF-Connecting-IP".
func New(trusted []net.IPNet, header string) (*Resolver, error) {
	header = strings.TrimSpace(header)
	if !validHeaderName(header) {
		return nil, fmt.Errorf("client IP header %q is not a valid header name", header)
	}
	header = http.CanonicalHeaderKey(header)
	r := &Resolver{trusted: trusted, header: header}
	if len(trusted) == 0 {
		return r, nil
	}
	var err error
	switch header {
	case "X-Forwarded-For", "Forwarded":
		r.strategy, err = realclientip.NewRightmostTrustedRangeStrategy(header, trusted)
	default:
		r.strategy, err = realclientip.NewSingleIPHeaderStrategy(header)
	}
	if err != nil {
		return nil, fmt.Errorf("client IP header %q: %w", header, err)
	}
	return r, nil
}

// validHeaderName: an RFC 9110 token (letters, digits and !#$%&'*+-.^_`|~), not empty.
func validHeaderName(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || strings.IndexByte("!#$%&'*+-.^_`|~", c) >= 0) {
			return false
		}
	}
	return true
}

// Key is the client of req, normalized: an IPv4-mapped IPv6 address is the IPv4 one and an IPv6 address counts as
// its /64 (whoever owns the range cannot dodge the limit by changing addresses inside it).
func (r *Resolver) Key(req *http.Request) string {
	peer := peerIP(req)
	if r == nil || r.strategy == nil || !r.isTrusted(peer) {
		return normalize(peer)
	}
	if headerLen(req.Header, r.header) > maxHeaderLen {
		return normalize(peer)
	}
	if ip := r.strategy.ClientIP(req.Header, req.RemoteAddr); ip != "" {
		return normalize(ip)
	}
	return normalize(peer) // header missing or useless: the proxy itself is the client (a stricter limit, never a looser one)
}

// PeerKey is the key when nothing is trusted: whoever opened the connection.
func PeerKey(req *http.Request) string { return normalize(peerIP(req)) }

func peerIP(req *http.Request) string {
	if ip := (realclientip.RemoteAddrStrategy{}).ClientIP(nil, req.RemoteAddr); ip != "" {
		return ip
	}
	return req.RemoteAddr
}

func (r *Resolver) isTrusted(ip string) bool {
	parsed := net.ParseIP(ip)
	if parsed == nil {
		return false
	}
	for i := range r.trusted {
		if r.trusted[i].Contains(parsed) {
			return true
		}
	}
	return false
}

func headerLen(h http.Header, name string) int {
	n := 0
	for _, v := range h[name] {
		n += len(v) + 1
	}
	return n
}

func normalize(ip string) string {
	addr, err := netip.ParseAddr(ip)
	if err != nil {
		return ip // not an address (a test or unix socket): count it as it is
	}
	addr = addr.WithZone("").Unmap()
	if addr.Is6() {
		p, _ := addr.Prefix(64)
		return p.Addr().String()
	}
	return addr.String()
}
