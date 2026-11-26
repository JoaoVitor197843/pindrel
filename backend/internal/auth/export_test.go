package auth

// DummyHash is the constant login verifies for an e-mail that does not exist.
const DummyHash = dummyHash

// HoldArgonSlots takes every Argon2 slot until release is called, so a test can reach the busy path without racing.
func HoldArgonSlots() (release func()) {
	argon.mu.RLock()
	slots := argon.slots
	argon.mu.RUnlock()
	for range cap(slots) {
		slots <- struct{}{}
	}
	return func() {
		for range cap(slots) {
			<-slots
		}
	}
}
