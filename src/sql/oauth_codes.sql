-- name: CreateAuthorizationCode :exec
INSERT INTO oauth_authorization_codes (code, client_id, user_id, redirect_uri, code_challenge, resource, scope, expires_at, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);

-- name: GetAuthorizationCode :one
SELECT code, client_id, user_id, redirect_uri, code_challenge, resource, scope, expires_at, created_at
FROM oauth_authorization_codes WHERE code = ?;

-- name: DeleteAuthorizationCode :exec
DELETE FROM oauth_authorization_codes WHERE code = ?;

-- name: DeleteExpiredCodes :exec
DELETE FROM oauth_authorization_codes WHERE expires_at < ?;
