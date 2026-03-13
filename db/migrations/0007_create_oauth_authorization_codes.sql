CREATE TABLE oauth_authorization_codes (
  code TEXT NOT NULL PRIMARY KEY,
  client_id TEXT NOT NULL REFERENCES oauth_clients(client_id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  redirect_uri TEXT NOT NULL,
  code_challenge TEXT NOT NULL,
  resource TEXT NOT NULL,
  scope TEXT NOT NULL DEFAULT '',
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
) STRICT;

CREATE INDEX idx_oauth_codes_client ON oauth_authorization_codes(client_id);
CREATE INDEX idx_oauth_codes_user ON oauth_authorization_codes(user_id);
