-- name: CreateRefreshToken :exec
INSERT INTO oauth_refresh_tokens (token_hash, client_id, user_id, resource, scope, expires_at, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?);

-- name: GetRefreshToken :one
SELECT token_hash, client_id, user_id, resource, scope, expires_at, revoked_at, created_at
FROM oauth_refresh_tokens WHERE token_hash = ?;

-- name: RevokeRefreshToken :exec
UPDATE oauth_refresh_tokens SET revoked_at = ? WHERE token_hash = ?;

-- name: DeleteExpiredRefreshTokens :exec
DELETE FROM oauth_refresh_tokens WHERE expires_at < ?;
