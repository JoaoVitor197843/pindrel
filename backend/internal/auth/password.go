package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/argon2"

	_ "embed"
)

var (
	ErrShortPassword  = errors.New("your password is short, please try another password")
	ErrServerBusy     = errors.New("too many password operations in progress, try again shortly")
	ErrInvalidHash    = errors.New("the stored password hash is malformed")
	ErrCommonPassword = errors.New("your password is common, please try another password")
)

// Each Argon2 run keeps ~19 MiB alive (argonMemory). Without a cap, N simultaneous logins cost
// N*19 MiB (measured: 16 -> 330 MiB, 64 -> 1 GiB), far over the RAM ceiling. Only argonSlots run at
// once; the others wait up to argonWait and then get ErrServerBusy (503), which is cheaper than an OOM kill.
const (
	defaultArgonSlots = 2
	defaultArgonWait  = 5 * time.Second
)

var argon = struct {
	mu    sync.RWMutex
	slots chan struct{}
	wait  time.Duration
}{slots: make(chan struct{}, defaultArgonSlots), wait: defaultArgonWait}

// SetArgonLimits changes how many Argon2 runs may happen at once and how long a request waits for a
// slot. It only affects operations started afterwards.
func SetArgonLimits(slots int, wait time.Duration) {
	argon.mu.Lock()
	defer argon.mu.Unlock()
	argon.slots = make(chan struct{}, max(1, slots))
	argon.wait = wait
}

// argonKey runs argon2id under the concurrency cap.
func argonKey(password, salt []byte, iterations, memory uint32, parallelism uint8, keyLen uint32) ([]byte, error) {
	argon.mu.RLock()
	slots, wait := argon.slots, argon.wait
	argon.mu.RUnlock()

	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case slots <- struct{}{}:
		defer func() { <-slots }()
	case <-timer.C:
		return nil, ErrServerBusy
	}
	return argon2.IDKey(password, salt, iterations, memory, parallelism, keyLen), nil
}

type hashParams struct {
	memory      uint32
	iterations  uint32
	parallelism uint8
	keyLen      uint32
	salt        []byte
	hash        []byte
}

const (
	argonMemory     = uint32(19456)
	argonIterations = uint32(2)
	argonParalelism = uint8(1)
	argonKeyLen     = uint32(32)
)

// One word per line, trimmed, byte-sorted (LC_ALL=C sort -u) and newline-terminated. It is searched in place
// with a binary search: a map of the 100k words cost ~4 MiB of live heap, this costs none (the text stays in the
// binary and only the pages a lookup touches are loaded).
//
//go:embed data/100k_most_common_passwords.txt
var commonPasswordsRaw string

func IsCommonPassword(password string) bool {
	return inSortedLines(commonPasswordsRaw, password)
}

// inSortedLines reports whether word is one of the lines of raw (sorted bytewise, each ending in '\n').
func inSortedLines(raw, word string) bool {
	if word == "" || strings.IndexByte(word, '\n') >= 0 {
		return false
	}
	lo, hi := 0, len(raw)
	for lo < hi {
		mid := lo + (hi-lo)/2
		start := strings.LastIndexByte(raw[:mid], '\n') + 1
		end := len(raw)
		if i := strings.IndexByte(raw[start:], '\n'); i >= 0 {
			end = start + i
		}
		switch line := raw[start:end]; {
		case line == word:
			return true
		case line < word:
			lo = end + 1
		default:
			hi = start
		}
	}
	return false
}
func CheckPassword(password string) (bool, error) {
	if len(password) < 8 {
		return false, ErrShortPassword
	}
	if IsCommonPassword(password) {
		return false, ErrCommonPassword
	}
	return true, nil
}
func HashPassword(password string) (string, error) {
	passed, err := CheckPassword(password)
	if !passed {
		return "", err
	}
	salt := make([]byte, 16)
	_, err = rand.Read(salt)
	if err != nil {
		return "", err
	}
	hash, err := argonKey([]byte(password), salt, argonIterations, argonMemory, argonParalelism, argonKeyLen)
	if err != nil {
		return "", err
	}
	saltB64 := base64.RawStdEncoding.EncodeToString(salt)
	hashB64 := base64.RawStdEncoding.EncodeToString(hash)
	encoded := fmt.Sprintf("%d$%d$%d$%d$%s$%s", argonMemory, argonIterations, argonParalelism, argonKeyLen, saltB64, hashB64)
	return encoded, nil
}

func VerifyPassword(hash, password string) (bool, error) {
	params := strings.Split(hash, "$")
	if len(params) != 6 {
		return false, ErrInvalidHash
	}
	var p hashParams
	memory, err := strconv.ParseUint(params[0], 10, 32)
	if err != nil {
		return false, err
	}
	p.memory = uint32(memory)
	iterations, err := strconv.ParseUint(params[1], 10, 32)
	if err != nil {
		return false, err
	}
	p.iterations = uint32(iterations)
	parallelism, err := strconv.ParseUint(params[2], 10, 8)
	if err != nil {
		return false, err
	}
	p.parallelism = uint8(parallelism)
	keyLen, err := strconv.ParseUint(params[3], 10, 32)
	if err != nil {
		return false, err
	}
	p.keyLen = uint32(keyLen)
	salt, err := base64.RawStdEncoding.DecodeString(params[4])
	if err != nil {
		return false, err
	}
	p.salt = salt
	originalHash, err := base64.RawStdEncoding.DecodeString(params[5])
	if err != nil {
		return false, err
	}
	p.hash = originalHash
	// argon2.IDKey panics on zero rounds/threads
	if p.iterations < 1 || p.parallelism < 1 || p.keyLen < 1 || p.memory < 1 {
		return false, ErrInvalidHash
	}
	compareHash, err := argonKey([]byte(password), p.salt, p.iterations, p.memory, p.parallelism, p.keyLen)
	if err != nil {
		return false, err
	}
	if subtle.ConstantTimeCompare(p.hash, compareHash) != 1 {
		return false, nil
	}
	return true, nil
}
