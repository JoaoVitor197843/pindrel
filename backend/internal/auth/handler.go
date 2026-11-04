package auth

import (
	"errors"
	"io"
	"log"
	"net/http"
	"pindrel/internal/api"
	"pindrel/internal/validator"
	"strings"
	"time"

	"pindrel/internal/api/dto"

	"google.golang.org/protobuf/proto"
)

// maxBodyBytes caps a request body. The largest valid auth payload is well under 1 KiB (e-mail 254,
// username 32 characters, password 72 bytes); the rest is slack. It keeps one request from using
// the instance's RAM.
const maxBodyBytes = 16 << 10

// readBody reads the (capped) body. On failure it has already written the response.
func readBody(w http.ResponseWriter, r *http.Request) ([]byte, bool) {
	defer r.Body.Close()
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			api.WriteError(w, http.StatusRequestEntityTooLarge, "payload_too_large", "request body is too large")
			return nil, false
		}
		// the client gave up or sent a broken body: its fault, not a server error
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "could not read request body")
		return nil, false
	}
	return body, true
}

type Handler struct {
	service         *Service
	jwtSecret       string
	accessExpireIn  time.Duration
	refreshExpireIn time.Duration
}

func NewHandler(service *Service, secret string, accessExp, refreshExp time.Duration) *Handler {
	return &Handler{
		service:         service,
		jwtSecret:       secret,
		accessExpireIn:  accessExp,
		refreshExpireIn: refreshExp,
	}
}

// Register godoc
// @Summary Create a new account
// @Description Register a new user, if the registration is enabled
// @Tags auth
// @Accept application/x-protobuf
// @Produce application/x-protobuf
// @Param input body dto.RegisterInput true "Register data"
// @Success 201 {object} dto.RegisterResponse
// @Failure 400 {object} dto.ErrorHttp
// @Failure 413 {object} dto.ErrorHttp
// @Failure 503 {object} dto.ErrorHttp
// @Failure 403 {object} dto.ErrorHttp
// @Failure 409 {object} dto.ErrorHttp
// @Router /auth/register/ [post]
func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	var input dto.RegisterInput
	if err := proto.Unmarshal(body, &input); err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "malformed request body")
		return
	}
	if err := validator.ValidateRegister(&input); err != nil {
		api.WriteError(w, http.StatusUnprocessableEntity, "validation_failed", err.Error())
		return
	}
	user, err := h.service.Register(r.Context(), input.Email, input.Username, input.Password)
	if err != nil {
		switch {
		case errors.Is(err, ErrRegistrationDisabled):
			api.WriteError(w, http.StatusForbidden, "registration_disabled", "Server registration is disabled")
		case errors.Is(err, ErrEmailAlreadyExists):
			api.WriteError(w, http.StatusConflict, "email_already_exists", "This email is already registered")
		case errors.Is(err, ErrShortPassword), errors.Is(err, ErrCommonPassword):
			api.WriteError(w, http.StatusBadRequest, "invalid_input", "password does not meet requirements")
		case errors.Is(err, ErrServerBusy):
			w.Header().Set("Retry-After", "5")
			api.WriteError(w, http.StatusServiceUnavailable, "server_busy", "server is busy, try again shortly")
		default:
			log.Printf("register error: %v", err)
			api.WriteError(w, http.StatusInternalServerError, "internal_error", "something went wrong")
		}
		return
	}
	api.WriteResponse(w, http.StatusCreated, &dto.RegisterResponse{
		User: &dto.UserSummary{
			Id:       user.ID.String(),
			Email:    user.Email,
			Username: user.Username,
		},
	})
}

// Login godoc
// @Summary Open Session
// @Description Authenticate the user and return the access in body and refresh token in httpOnly cookie
// @Tags auth
// @Accept application/x-protobuf
// @Produce application/x-protobuf
// @Param input body dto.LoginInput true "Login credentials"
// @Success 200 {object} dto.LoginRefreshResponse
// @Failure 400 {object} dto.ErrorHttp
// @Failure 401 {object} dto.ErrorHttp
// @Failure 413 {object} dto.ErrorHttp
// @Failure 503 {object} dto.ErrorHttp
// @Router /auth/login/ [post]
func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	var input dto.LoginInput
	if err := proto.Unmarshal(body, &input); err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "malformed request body")
		return
	}
	if err := validator.ValidateLogin(&input); err != nil {
		api.WriteError(w, http.StatusUnprocessableEntity, "validation_failed", err.Error())
		return
	}
	tokens, err := h.service.Login(r.Context(), input.Email, input.Password, h.jwtSecret, h.accessExpireIn, h.refreshExpireIn)
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidCredentials):
			api.WriteError(w, http.StatusUnauthorized, "invalid_credentials", "Invalid email or password")
		case errors.Is(err, ErrServerBusy):
			w.Header().Set("Retry-After", "5")
			api.WriteError(w, http.StatusServiceUnavailable, "server_busy", "server is busy, try again shortly")
		default:
			log.Printf("login error: %v", err)
			api.WriteError(w, http.StatusInternalServerError, "internal_error", "something went wrong")
		}
		return
	}
	http.SetCookie(w, &http.Cookie{
		Name:     "refresh_token",
		Value:    tokens.RefreshToken,
		HttpOnly: true,
		Secure:   secureRequest(r),
		SameSite: http.SameSiteLaxMode,
		Path:     "/",
		MaxAge:   int(h.refreshExpireIn.Seconds()),
	})
	api.WriteResponse(w, http.StatusOK, &dto.LoginRefreshResponse{
		AccessToken: tokens.AccessToken,
		ExpiresIn:   int32(h.accessExpireIn.Seconds()),
	})
}

// Logout godoc
// @Summary Close the session
// @Description Invalidates the refresh token (and the access token, if sended) and clear the cookie
// @Tags auth
// @Produce application/x-protobuf
// @Success 204 "No Content"
// @Failure 401 {object} dto.ErrorHttp
// @Router /auth/logout/ [post]
func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	refreshToken, err := ExtractToken(r)
	if err != nil {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}

	accessToken, _ := ExtractBearerToken(r)
	if err := h.service.Logout(r.Context(), refreshToken, accessToken, h.jwtSecret); err != nil {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:     "refresh_token",
		Value:    "",
		HttpOnly: true,
		Secure:   secureRequest(r),
		SameSite: http.SameSiteLaxMode,
		Path:     "/",
		MaxAge:   -1,
	})
	w.WriteHeader(http.StatusNoContent)
}

// Refresh godoc
// @Summary Renews the access token
// @Description Change one valid refresh token for a new access token
// @Tags auth
// @Produce application/x-protobuf
// @Success 200 {object} dto.LoginRefreshResponse
// @Failure 401 {object} dto.ErrorHttp
// @Router /auth/refresh/ [post]
func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	tokenString, err := ExtractToken(r)
	if err != nil {
		api.WriteError(w, http.StatusUnauthorized, "invalid_refresh_token", "no valid token found")
		return
	}
	accessToken, err := h.service.Refresh(r.Context(), tokenString, h.jwtSecret, h.accessExpireIn)
	if err != nil {
		switch {
		case errors.Is(err, ErrUserNotFound):
			api.WriteError(w, http.StatusUnauthorized, "invalid_refresh_token", "user no longer exists")
		default:
			api.WriteError(w, http.StatusUnauthorized, "invalid_refresh_token", "no valid token found")
		}
		return
	}
	api.WriteResponse(w, http.StatusOK, &dto.LoginRefreshResponse{
		AccessToken: accessToken,
		ExpiresIn:   int32(h.accessExpireIn.Seconds()),
	})
}

// Me godoc
// @Summary Current user data
// @Description Returns the user data associated with the session access token
// @Tags auth
// @Produce application/x-protobuf
// @Security BearerAuth
// @Success 200 {object} dto.UserSummary
// @Failure 401 {object} dto.ErrorHttp
// @Router /auth/me/ [get]
func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	tokenString, err := ExtractBearerToken(r)
	if err != nil {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	user, err := h.service.Me(r.Context(), tokenString, h.jwtSecret)
	if err != nil {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	api.WriteResponse(w, http.StatusOK, &dto.UserSummary{
		Id:       user.ID.String(),
		Email:    user.Email,
		Username: user.Username,
	})
}

// secureRequest says whether the client reached the server over TLS: directly, or through the gateway (or a tunnel),
// which ends the TLS itself and says so in X-Forwarded-Proto. The cookie is then marked Secure, so the browser never
// sends it over plain HTTP. The header is trusted without a list of proxies because the only thing a forged one can do is
// make the forger's own cookie Secure.
func secureRequest(r *http.Request) bool {
	return r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
}
