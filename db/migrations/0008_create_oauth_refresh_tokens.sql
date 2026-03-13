CREATE TABLE oauth_refresh_tokens (
  token_hash TEXT NOT NULL PRIMARY KEY,
  client_id TEXT NOT NULL REFERENCES oauth_clients(client_id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  resource TEXT NOT NULL DEFAULT '',
  scope TEXT NOT NULL DEFAULT '',
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER,
  created_at INTEGER NOT NULL
) STRICT;

CREATE INDEX idx_refresh_tokens_client ON oauth_refresh_tokens(client_id);
CREATE INDEX idx_refresh_tokens_user ON oauth_refresh_tokens(user_id);
