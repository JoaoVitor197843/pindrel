package files

import (
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestSignedLink_ValidForItsFileAndItsTimeOnly(t *testing.T) {
	secret := []byte("segredo")
	id := uuid.New()
	now := time.Now()
	exp, sig := SignLink(secret, id, now.Add(10*time.Minute))
	if !VerifyLink(secret, id, exp, sig, now) {
		t.Fatal("a fresh link must verify")
	}
	for name, ok := range map[string]bool{
		"other file":                 VerifyLink(secret, uuid.New(), exp, sig, now),
		"other secret":               VerifyLink([]byte("outro"), id, exp, sig, now),
		"later exp":                  VerifyLink(secret, id, exp+3600, sig, now),
		"expired":                    VerifyLink(secret, id, exp, sig, now.Add(11*time.Minute)),
		"empty sig":                  VerifyLink(secret, id, exp, "", now),
		"short sig":                  VerifyLink(secret, id, exp, sig[:10], now),
		"not hex":                    VerifyLink(secret, id, exp, strings.Repeat("zz", 32), now),
		"upper hex of a wrong value": VerifyLink(secret, id, exp, strings.ToUpper(strings.Repeat("ab", 32)), now),
	} {
		if ok {
			t.Errorf("%s must not verify", name)
		}
	}
	// the last second is still inside the window
	if !VerifyLink(secret, id, exp, sig, time.Unix(exp, 0)) {
		t.Error("the second of expiry still works")
	}
}

func TestSignedLink_SecretsOfAnyShapeNeverPanic(t *testing.T) {
	for _, s := range [][]byte{nil, {}, []byte("a"), make([]byte, 4096)} {
		exp, sig := SignLink(s, uuid.Nil, time.Unix(0, 0))
		if !VerifyLink(s, uuid.Nil, exp, sig, time.Unix(0, 0)) {
			t.Errorf("secret of %d bytes", len(s))
		}
	}
}
