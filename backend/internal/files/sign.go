package files

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// A download address is a capability: whoever holds it can read that one file until it expires, and nothing else. Who may
// get one is decided when it is made (the owner, and later whoever a shared page lets in), so no token of the session
// travels in an <img>, <video> or link. HMAC with the server secret, so any replica can check it and none keeps state.

func signature(secret []byte, id uuid.UUID, exp int64) []byte {
	m := hmac.New(sha256.New, secret)
	fmt.Fprintf(m, "pindrel-file-v1\x00%s\x00%d", id, exp)
	return m.Sum(nil)
}

// SignLink returns the exp (unix seconds) and the hex signature of a download address.
func SignLink(secret []byte, id uuid.UUID, until time.Time) (int64, string) {
	exp := until.Unix()
	return exp, hex.EncodeToString(signature(secret, id, exp))
}

// VerifyLink reports whether the address is genuine and still valid.
func VerifyLink(secret []byte, id uuid.UUID, exp int64, sig string, now time.Time) bool {
	got, err := hex.DecodeString(sig)
	if err != nil || len(got) != sha256.Size {
		return false
	}
	if !hmac.Equal(got, signature(secret, id, exp)) {
		return false
	}
	return now.Unix() <= exp
}
