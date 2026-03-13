-- name: GetUserById :one
SELECT id, email, created_at, updated_at
FROM users WHERE id = ?;

-- name: CreateUser :one
INSERT INTO users (email, created_at, updated_at)
VALUES (?, ?, ?)
RETURNING id, email, created_at, updated_at;

-- name: DeleteOldUsers :exec
DELETE FROM users WHERE created_at < ?;
