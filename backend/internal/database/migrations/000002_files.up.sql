-- Files on disk (internal/files). The bytes are in FILES_DIR, named by their SHA-256; this table says who owns them.
CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sha256 BYTEA NOT NULL CHECK (octet_length(sha256) = 32),
    size BIGINT NOT NULL CHECK (size >= 0),
    -- decided by the server from the bytes, never taken from the client
    mime TEXT NOT NULL,
    -- 1 plays or shows inside the page, 2 and 3 only download (see internal/files/classify.go)
    level SMALLINT NOT NULL CHECK (level BETWEEN 1 AND 3),
    name TEXT NOT NULL DEFAULT '',
    -- a vault file: bytes the device encrypted; the server never looks inside
    encrypted BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- set when nothing uses the file any more; the clean-up removes it after a grace period
    orphan_since TIMESTAMPTZ
);

CREATE INDEX idx_files_user_created ON files(user_id, created_at DESC, id DESC);
CREATE INDEX idx_files_sha256 ON files(sha256);
CREATE INDEX idx_files_orphan ON files(orphan_since) WHERE orphan_since IS NOT NULL;

-- Uploads in progress. The pieces are in FILES_DIR/uploads/<id>/; `received` has one bit per piece, so any replica can
-- take any piece and the API keeps no state of its own.
CREATE TABLE uploads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    size BIGINT NOT NULL CHECK (size > 0),
    chunk_size INTEGER NOT NULL CHECK (chunk_size > 0),
    chunk_count INTEGER NOT NULL CHECK (chunk_count > 0),
    received BYTEA NOT NULL,
    name TEXT NOT NULL DEFAULT '',
    encrypted BOOLEAN NOT NULL DEFAULT false,
    -- 'open' takes pieces; 'finishing' is claimed by exactly one request that is joining the pieces
    state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'finishing')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_uploads_user ON uploads(user_id);
CREATE INDEX idx_uploads_expires ON uploads(expires_at);
