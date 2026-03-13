-- name: GetUserEmailByEmail :one
SELECT id, email, user_id, token_hash, token_expires_at,
       previous_token_hash, verified_at, created_at
FROM user_emails WHERE email = ?;

-- name: CreateUserEmail :one
INSERT INTO user_emails (email, created_at)
VALUES (?, ?)
RETURNING id, email, user_id, token_hash, token_expires_at,
          previous_token_hash, verified_at, created_at;

-- name: SetVerificationToken :exec
UPDATE user_emails
SET token_hash = ?, token_expires_at = ?, previous_token_hash = token_hash
WHERE email = ?;

-- name: VerifyUserEmail :exec
UPDATE user_emails
SET verified_at = ?, token_hash = NULL, token_expires_at = NULL, previous_token_hash = NULL
WHERE email = ?;

-- name: ClaimUserEmail :exec
UPDATE user_emails
SET user_id = ?
WHERE email = ? AND user_id IS NULL;

-- name: DeleteUserEmailsForOldUsers :exec
DELETE FROM user_emails WHERE user_id IN (
  SELECT u.id FROM users u WHERE u.created_at < ?
);
