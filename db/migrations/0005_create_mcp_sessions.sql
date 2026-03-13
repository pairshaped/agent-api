CREATE TABLE mcp_sessions (
  session_id TEXT NOT NULL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
) STRICT;

CREATE INDEX idx_mcp_sessions_user ON mcp_sessions(user_id);
