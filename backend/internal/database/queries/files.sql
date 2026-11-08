-- name: QuotaUsed :one
-- Everything a user holds: finished files plus uploads still open (their size is already promised).
SELECT (
    COALESCE((SELECT SUM(f.size) FROM files f WHERE f.user_id = $1), 0) +
    COALESCE((SELECT SUM(u.size) FROM uploads u WHERE u.user_id = $1), 0)
)::bigint AS used;

-- name: LockUser :exec
-- Serialises quota checks of one user across replicas: two uploads started together cannot both pass the limit.
SELECT id FROM users WHERE id = $1 FOR UPDATE;

-- name: CountOpenUploads :one
SELECT count(*) FROM uploads WHERE user_id = $1;

-- name: CreateUpload :one
INSERT INTO uploads (user_id, size, chunk_size, chunk_count, received, name, encrypted, expires_at)
VALUES ($1, $2, $3, $4, decode(repeat('00', (($4 + 7) / 8)::int), 'hex'), $5, $6, $7)
RETURNING id, user_id, size, chunk_size, chunk_count, received, name, encrypted, state, created_at, updated_at, expires_at;

-- name: GetUpload :one
SELECT id, user_id, size, chunk_size, chunk_count, received, name, encrypted, state, created_at, updated_at, expires_at
FROM uploads WHERE id = $1 AND user_id = $2;

-- name: MarkChunkReceived :one
-- One statement, one row lock: pieces that arrive together on different replicas never lose each other's bit.
-- Bit n is bit (n % 8) of byte (n / 8), least significant first, and set_bit(bytea) counts the same way.
UPDATE uploads
SET received = set_bit(received, $3::int, 1), updated_at = now(), expires_at = $4
WHERE id = $1 AND user_id = $2 AND state = 'open'
RETURNING received;

-- name: ClaimUploadForFinish :one
-- Exactly one request wins the right to join the pieces.
UPDATE uploads SET state = 'finishing', updated_at = now()
WHERE id = $1 AND user_id = $2 AND state = 'open'
RETURNING id, user_id, size, chunk_size, chunk_count, received, name, encrypted, state, created_at, updated_at, expires_at;

-- name: ReopenUpload :exec
UPDATE uploads SET state = 'open', updated_at = now(), expires_at = $3 WHERE id = $1 AND user_id = $2 AND state = 'finishing';

-- name: DeleteUpload :one
DELETE FROM uploads WHERE id = $1 AND user_id = $2 RETURNING id;

-- name: DeleteUploadByID :exec
DELETE FROM uploads WHERE id = $1;

-- name: ExpiredUploads :many
SELECT id FROM uploads WHERE expires_at < now() ORDER BY expires_at LIMIT $1;

-- name: CreateFile :one
INSERT INTO files (user_id, sha256, size, mime, level, name, encrypted)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING id, user_id, sha256, size, mime, level, name, encrypted, created_at, orphan_since;

-- name: GetFile :one
SELECT id, user_id, sha256, size, mime, level, name, encrypted, created_at, orphan_since FROM files WHERE id = $1;

-- name: ListFiles :many
SELECT id, user_id, sha256, size, mime, level, name, encrypted, created_at, orphan_since
FROM files
WHERE user_id = $1 AND (created_at, id) < ($2::timestamptz, $3::uuid)
ORDER BY created_at DESC, id DESC
LIMIT $4;

-- name: DeleteFile :one
DELETE FROM files WHERE id = $1 AND user_id = $2 RETURNING sha256;

-- name: CountFilesWithHash :one
SELECT count(*) FROM files WHERE sha256 = $1;

-- name: MarkFileOrphan :exec
UPDATE files SET orphan_since = COALESCE(orphan_since, now()) WHERE id = $1 AND user_id = $2;

-- name: ClearFileOrphan :exec
UPDATE files SET orphan_since = NULL WHERE id = $1 AND user_id = $2;

-- name: OrphanFilesDue :many
SELECT id, user_id, sha256 FROM files WHERE orphan_since IS NOT NULL AND orphan_since < $1 ORDER BY orphan_since LIMIT $2;

-- name: DeleteFileByID :exec
DELETE FROM files WHERE id = $1;

-- name: UploadExists :one
SELECT EXISTS (SELECT 1 FROM uploads WHERE id = $1);
