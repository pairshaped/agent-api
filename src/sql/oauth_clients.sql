-- name: CreateOauthClient :exec
INSERT INTO oauth_clients (client_id, client_secret_hash, client_secret_expires_at, redirect_uris, client_name, token_endpoint_auth_method, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?);

-- name: GetOauthClient :one
SELECT client_id, client_secret_hash, client_secret_expires_at, redirect_uris, client_name, token_endpoint_auth_method, created_at
FROM oauth_clients WHERE client_id = ?;
