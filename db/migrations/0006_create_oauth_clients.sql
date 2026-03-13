CREATE TABLE oauth_clients (
  client_id TEXT NOT NULL PRIMARY KEY,
  client_secret_hash TEXT,
  client_secret_expires_at INTEGER NOT NULL DEFAULT 0,
  redirect_uris TEXT NOT NULL,
  client_name TEXT NOT NULL,
  token_endpoint_auth_method TEXT NOT NULL DEFAULT 'none',
  created_at INTEGER NOT NULL
) STRICT;
