package auth_test

import (
	"pindrel/internal/auth"
	"testing"
)

func TestVerifyPassword_CorrectPassword_ReturnsTrue(t *testing.T) {
	hash, err := auth.HashPassword("Appo1736@")
	if err != nil {
		t.Fatal("Password failed on hashing")
	}
	passed, err := auth.VerifyPassword(hash, "Appo1736@")
	if err != nil {
		t.Fatal("Password failed to verify")
	}
	if !passed {
		t.Fatalf("expected password to match, got passed=%v", passed)
	}
}
func TestHashPassword_CommonPassword_ReturnsFalse(t *testing.T) {
	_, err := auth.HashPassword("12345678")
	if err == nil {
		t.Fatal("expected password failed to hash, got hashed")
	}
}

func TestHashPassword_ShortPassword_ReturnsFalse(t *testing.T) {
	_, err := auth.HashPassword("1234")
	if err == nil {
		t.Fatal("expected password failed to hash, got hashed")
	}
}

func TestVerifyPassword_WrongPassword_ReturnsFalse(t *testing.T) {
	hash, err := auth.HashPassword("Appo1736@")
	if err != nil {
		t.Fatal("Password failed on hashing")
	}
	passed, err := auth.VerifyPassword(hash, "123")
	if err != nil {
		t.Fatal("Password failed to verify")
	}
	if passed {
		t.Fatalf("expected password to not match, got passed=%v", passed)
	}
}
