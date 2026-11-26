package auth

// LoginResult is what a successful login hands to the handler: the access token goes in the body, the refresh token in
// the HttpOnly cookie. The wire types are in internal/api/dto (generated from shared/protos).
type LoginResult struct {
	RefreshToken string
	AccessToken  string
}
