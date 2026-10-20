package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"

	_ "embed"
)

var (
	ErrShortPassword  = errors.New("your password is short, please try another password")
	ErrCommonPassword = errors.New("your password is common, please try another password")
)

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

//go:embed data/100k_most_common_passwords.txt
var commonPasswordsRaw string

var commonPasswords = buildSet(commonPasswordsRaw)

func buildSet(raw string) map[string]struct{} {
	lines := strings.Split(raw, "\n")
	set := make(map[string]struct{}, len(lines))
	for _, line := range lines {
		set[strings.TrimSpace(line)] = struct{}{}
	}
	return set
}
func IsCommonPassword(password string) bool {
	_, found := commonPasswords[password]
	return found
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
	hash := argon2.IDKey([]byte(password), salt, argonIterations, argonMemory, argonParalelism, argonKeyLen)
	saltB64 := base64.RawStdEncoding.EncodeToString(salt)
	hashB64 := base64.RawStdEncoding.EncodeToString(hash)
	encoded := fmt.Sprintf("%d$%d$%d$%d$%s$%s", argonMemory, argonIterations, argonParalelism, argonKeyLen, saltB64, hashB64)
	return encoded, nil
}

func VerifyPassword(hash, password string) (bool, error) {
	params := strings.Split(hash, "$")
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
	compareHash := argon2.IDKey([]byte(password), p.salt, p.iterations, p.memory, p.parallelism, p.keyLen)
	if subtle.ConstantTimeCompare(p.hash, compareHash) != 1 {
		return false, nil
	}
	return true, nil
}
