-- name: CreateMcpSession :exec
INSERT INTO mcp_sessions (session_id, user_id, created_at, last_seen_at)
VALUES (?, ?, ?, ?);

-- name: GetMcpSession :one
SELECT session_id, user_id, created_at, last_seen_at
FROM mcp_sessions WHERE session_id = ?;

-- name: TouchMcpSession :exec
UPDATE mcp_sessions SET last_seen_at = ? WHERE session_id = ?;

-- name: DeleteMcpSession :exec
DELETE FROM mcp_sessions WHERE session_id = ?;

-- name: DeleteOldMcpSessions :exec
DELETE FROM mcp_sessions WHERE last_seen_at < ?;
