CREATE TABLE user_emails (
  id INTEGER PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  user_id INTEGER,
  token_hash TEXT,
  token_expires_at INTEGER,
  previous_token_hash TEXT,
  verified_at INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
) STRICT;

CREATE INDEX idx_user_emails_email ON user_emails(email);
CREATE INDEX idx_user_emails_user ON user_emails(user_id);
