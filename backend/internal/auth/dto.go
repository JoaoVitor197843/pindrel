package auth

type UserSummary struct {
	ID       string `json:"id"`
	Email    string `json:"email"`
	Username string `json:"username"`
}

type RegisterResponse struct {
	User UserSummary `json:"user"`
}
