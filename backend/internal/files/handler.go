package files

import (
	"encoding/hex"
	"errors"
	"io"
	"log"
	"mime"
	"net/http"
	"strconv"
	"time"

	"pindrel/internal/api"
	"pindrel/internal/api/dto"
	"pindrel/internal/database/db"
	contextkeys "pindrel/pkg/context"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
)

const (
	// maxBodyBytes caps the small protobuf requests; pieces have their own cap.
	maxBodyBytes = 4 << 10
	// A piece is read with its own, longer deadline than the server's 10 s, which a phone on a bad line may need.
	chunkReadWindow = 60 * time.Second
	// A download keeps going while bytes keep moving: every write pushes the deadline forward, so a 1 GiB file is never cut
	// off by a clock, and a reader that stalls is dropped.
	downloadWriteWindow = 30 * time.Second
	listLimit           = 50
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func userID(r *http.Request) (uuid.UUID, bool) {
	id, ok := r.Context().Value(contextkeys.UserIDKey).(uuid.UUID)
	return id, ok
}

func readProto(w http.ResponseWriter, r *http.Request, into proto.Message) bool {
	defer r.Body.Close()
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			api.WriteError(w, http.StatusRequestEntityTooLarge, "payload_too_large", "request body is too large")
		} else {
			api.WriteError(w, http.StatusBadRequest, "invalid_input", "could not read request body")
		}
		return false
	}
	if err := proto.Unmarshal(body, into); err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "malformed request")
		return false
	}
	return true
}

func parseID(w http.ResponseWriter, raw string) (uuid.UUID, bool) {
	id, err := uuid.Parse(raw)
	if err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "invalid id")
		return uuid.Nil, false
	}
	return id, true
}

// fail maps a service error to its answer; anything unexpected is logged and reported as a plain 500.
func fail(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrInvalidInput):
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "invalid input")
	case errors.Is(err, ErrTooLarge):
		api.WriteError(w, http.StatusRequestEntityTooLarge, "file_too_large", "the file is larger than this server accepts")
	case errors.Is(err, ErrQuota):
		api.WriteError(w, http.StatusRequestEntityTooLarge, "quota_exceeded", "not enough space left in your quota")
	case errors.Is(err, ErrDiskFull):
		api.WriteError(w, http.StatusInsufficientStorage, "storage_full", "the server is out of space")
	case errors.Is(err, ErrTooMany):
		api.WriteError(w, http.StatusTooManyRequests, "too_many_uploads", "too many uploads open at once")
	case errors.Is(err, ErrUploadMissing):
		api.WriteError(w, http.StatusNotFound, "upload_not_found", "upload not found")
	case errors.Is(err, ErrUploadBusy):
		api.WriteError(w, http.StatusConflict, "upload_busy", "the upload is being finished")
	case errors.Is(err, ErrChunkRange):
		api.WriteError(w, http.StatusBadRequest, "chunk_out_of_range", "piece number out of range")
	case errors.Is(err, ErrBadChunkSize):
		api.WriteError(w, http.StatusBadRequest, "bad_chunk_size", "the piece has the wrong size")
	case errors.Is(err, ErrChunkHash):
		api.WriteError(w, http.StatusUnprocessableEntity, "chunk_hash_mismatch", "the piece does not match its hash")
	case errors.Is(err, ErrIncomplete):
		api.WriteError(w, http.StatusConflict, "upload_incomplete", "some pieces are missing")
	case errors.Is(err, ErrFileMissing):
		api.WriteError(w, http.StatusNotFound, "file_not_found", "file not found")
	case errors.Is(err, ErrBadLink):
		api.WriteError(w, http.StatusForbidden, "link_invalid", "the download address is not valid")
	default:
		log.Printf("files: %v", err)
		api.WriteError(w, http.StatusInternalServerError, "internal_error", "internal error")
	}
}

func info(f db.File) *dto.FileInfo {
	return &dto.FileInfo{Id: f.ID.String(), Size: f.Size, Mime: f.Mime, Level: int32(f.Level), Name: f.Name, Encrypted: f.Encrypted, CreatedAt: f.CreatedAt.Time.UnixMilli()}
}

// CreateUpload — POST /files/uploads/
func (h *Handler) CreateUpload(w http.ResponseWriter, r *http.Request) {
	user, ok := userID(r)
	if !ok {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	var in dto.CreateUploadRequest
	if !readProto(w, r, &in) {
		return
	}
	if len(in.Name) > 1024 {
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "name too long")
		return
	}
	up, err := h.svc.CreateUpload(r.Context(), user, in.Size, in.Name, in.Encrypted)
	if err != nil {
		fail(w, err)
		return
	}
	api.WriteResponse(w, http.StatusCreated, &dto.CreateUploadResponse{UploadId: up.ID.String(), ChunkSize: up.ChunkSize, ChunkCount: up.ChunkCount})
}

// UploadStatus — GET /files/uploads/{id}
func (h *Handler) UploadStatus(w http.ResponseWriter, r *http.Request) {
	user, ok := userID(r)
	id, okID := parseID(w, chi.URLParam(r, "id"))
	if !okID {
		return
	}
	if !ok {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	up, err := h.svc.Upload(r.Context(), user, id)
	if err != nil {
		fail(w, err)
		return
	}
	api.WriteResponse(w, http.StatusOK, &dto.UploadStatus{UploadId: up.ID.String(), Size: up.Size, ChunkSize: up.ChunkSize, ChunkCount: up.ChunkCount, Received: up.Received})
}

// PutChunk — PUT /files/uploads/{id}/{n}, the body is the raw bytes of the piece.
func (h *Handler) PutChunk(w http.ResponseWriter, r *http.Request) {
	user, ok := userID(r)
	id, okID := parseID(w, chi.URLParam(r, "id"))
	if !okID {
		return
	}
	if !ok {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	n, err := strconv.Atoi(chi.URLParam(r, "n"))
	if err != nil || n < 0 {
		api.WriteError(w, http.StatusBadRequest, "chunk_out_of_range", "piece number out of range")
		return
	}
	sum, err := hex.DecodeString(r.Header.Get("X-Chunk-Sha256"))
	if err != nil || len(sum) != 32 {
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "X-Chunk-Sha256 must be the hex SHA-256 of the piece")
		return
	}
	if r.ContentLength > ChunkSize {
		api.WriteError(w, http.StatusRequestEntityTooLarge, "payload_too_large", "a piece is at most 512 KiB")
		return
	}
	_ = http.NewResponseController(w).SetReadDeadline(time.Now().Add(chunkReadWindow))
	defer r.Body.Close()
	if err := h.svc.PutChunk(r.Context(), user, id, n, http.MaxBytesReader(w, r.Body, ChunkSize+1), sum); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			err = ErrBadChunkSize
		}
		fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Finish — POST /files/uploads/{id}/finish
func (h *Handler) Finish(w http.ResponseWriter, r *http.Request) {
	user, ok := userID(r)
	id, okID := parseID(w, chi.URLParam(r, "id"))
	if !okID {
		return
	}
	if !ok {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	// joining a large file takes longer than the server's default window
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(10 * time.Minute))
	f, err := h.svc.Finish(r.Context(), user, id)
	if err != nil {
		fail(w, err)
		return
	}
	api.WriteResponse(w, http.StatusCreated, &dto.FinishUploadResponse{File: info(f)})
}

// CancelUpload — DELETE /files/uploads/{id}
func (h *Handler) CancelUpload(w http.ResponseWriter, r *http.Request) {
	user, ok := userID(r)
	id, okID := parseID(w, chi.URLParam(r, "id"))
	if !okID {
		return
	}
	if !ok {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	if err := h.svc.Cancel(r.Context(), user, id); err != nil {
		fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// List — GET /files/?after=<created ms>&after_id=<uuid>
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	user, ok := userID(r)
	if !ok {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	after, afterID := time.Now().Add(24*time.Hour), uuid.Max
	if c := r.URL.Query().Get("after"); c != "" {
		ms, err := strconv.ParseInt(c, 10, 64)
		id, err2 := uuid.Parse(r.URL.Query().Get("after_id"))
		if err != nil || err2 != nil {
			api.WriteError(w, http.StatusBadRequest, "invalid_input", "invalid cursor")
			return
		}
		after, afterID = time.UnixMilli(ms), id
	}
	rows, used, err := h.svc.List(r.Context(), user, after, afterID, listLimit+1)
	if err != nil {
		fail(w, err)
		return
	}
	out := &dto.ListFilesResponse{UsedBytes: used, QuotaBytes: h.svc.Quota()}
	for i, f := range rows {
		if i == listLimit {
			last := rows[listLimit-1]
			out.NextCursor = strconv.FormatInt(last.CreatedAt.Time.UnixMilli(), 10) + "." + last.ID.String()
			break
		}
		out.Files = append(out.Files, info(f))
	}
	api.WriteResponse(w, http.StatusOK, out)
}

// Link — POST /files/{id}/link
func (h *Handler) Link(w http.ResponseWriter, r *http.Request) {
	user, ok := userID(r)
	id, okID := parseID(w, chi.URLParam(r, "id"))
	if !okID {
		return
	}
	if !ok {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	url, until, err := h.svc.Link(r.Context(), user, id)
	if err != nil {
		fail(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	api.WriteResponse(w, http.StatusOK, &dto.FileLinkResponse{Url: url, ExpiresAt: until.UnixMilli()})
}

// Delete — DELETE /files/{id}
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	user, ok := userID(r)
	id, okID := parseID(w, chi.URLParam(r, "id"))
	if !okID {
		return
	}
	if !ok {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	if err := h.svc.Delete(r.Context(), user, id); err != nil {
		fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// SetOrphan — PUT /files/{id}/orphan (nothing uses it any more) and DELETE /files/{id}/orphan (it is used again).
func (h *Handler) SetOrphan(orphan bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, ok := userID(r)
		id, okID := parseID(w, chi.URLParam(r, "id"))
		if !okID {
			return
		}
		if !ok {
			api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
			return
		}
		if err := h.svc.MarkOrphan(r.Context(), user, id, orphan); err != nil {
			fail(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// slidingWriter pushes the write deadline forward on every write, so the window counts from the last byte that moved.
type slidingWriter struct {
	http.ResponseWriter
	rc *http.ResponseController
}

func (w slidingWriter) Write(p []byte) (int, error) {
	_ = w.rc.SetWriteDeadline(time.Now().Add(downloadWriteWindow))
	return w.ResponseWriter.Write(p)
}

func (w slidingWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

func disposition(kind, name string) string {
	if v := mime.FormatMediaType(kind, map[string]string{"filename": name}); v != "" && name != "" {
		return v
	}
	return kind
}

// Download — GET|HEAD /files/{id}?exp=&sig=. No session: the signed address is the permission.
func (h *Handler) Download(w http.ResponseWriter, r *http.Request) {
	id, ok := parseID(w, chi.URLParam(r, "id"))
	if !ok {
		return
	}
	exp, err := strconv.ParseInt(r.URL.Query().Get("exp"), 10, 64)
	if err != nil {
		fail(w, ErrBadLink)
		return
	}
	fd, f, err := h.svc.Open(r.Context(), id, exp, r.URL.Query().Get("sig"))
	if err != nil {
		fail(w, err)
		return
	}
	defer fd.Close()

	hd := w.Header()
	hd.Set("X-Content-Type-Options", "nosniff")
	hd.Set("ETag", `"`+hex.EncodeToString(f.Sha256)+`"`)
	hd.Set("Cache-Control", "private, max-age=600")
	hd.Set("Cross-Origin-Resource-Policy", "same-origin")
	level, mimeType := Level(f.Level), f.Mime
	switch {
	case f.Encrypted || level == LevelOther:
		// bytes the server cannot vouch for: the browser may only save them
		mimeType = "application/octet-stream"
		hd.Set("Content-Disposition", disposition("attachment", f.Name))
		hd.Set("Content-Security-Policy", "sandbox; default-src 'none'")
	case level == LevelDocument:
		hd.Set("Content-Disposition", disposition("attachment", f.Name))
		hd.Set("Content-Security-Policy", "sandbox; default-src 'none'")
	default:
		hd.Set("Content-Disposition", disposition("inline", f.Name))
		if mimeType == "application/pdf" {
			// the browser's PDF viewer does not run under `sandbox`
			hd.Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src data: blob:")
		} else {
			hd.Set("Content-Security-Policy", "sandbox; default-src 'none'")
		}
	}
	hd.Set("Content-Type", mimeType)
	rc := http.NewResponseController(w)
	_ = rc.SetWriteDeadline(time.Now().Add(downloadWriteWindow))
	http.ServeContent(slidingWriter{ResponseWriter: w, rc: rc}, r, "", f.CreatedAt.Time, fd)
}
