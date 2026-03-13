import gleam/string
import gleam_mcp_todo/auth

// --- Verification Token Tests ---

pub fn should_generate_5_char_token_test() {
  let token = auth.generate_verification_code()
  assert string.length(token) == 5
}

pub fn should_hash_token_deterministically_test() {
  let hash1 = auth.hash_token(email: "test@example.com", token: "ABC12")
  let hash2 = auth.hash_token(email: "test@example.com", token: "ABC12")
  assert hash1 == hash2
}

pub fn should_hash_token_case_insensitively_test() {
  let hash1 = auth.hash_token(email: "test@example.com", token: "abc12")
  let hash2 = auth.hash_token(email: "test@example.com", token: "ABC12")
  assert hash1 == hash2
}

pub fn should_produce_different_hashes_for_different_emails_test() {
  let hash1 = auth.hash_token(email: "alice@example.com", token: "ABC12")
  let hash2 = auth.hash_token(email: "bob@example.com", token: "ABC12")
  assert hash1 != hash2
}

// --- Access Token Tests (Resource-bound) ---

pub fn should_create_and_validate_access_token_test() {
  let secret = "test-secret"
  let now = 1_000_000
  let resource = "http://localhost:8080"
  let token =
    auth.create_access_token(
      session_secret: secret,
      user_id: 42,
      resource: resource,
      now: now,
    )

  let assert Ok(42) =
    auth.validate_access_token(
      session_secret: secret,
      token: token,
      resource: resource,
      now: now,
    )
}

pub fn should_reject_access_token_wrong_resource_test() {
  let secret = "test-secret"
  let now = 1_000_000
  let token =
    auth.create_access_token(
      session_secret: secret,
      user_id: 42,
      resource: "http://localhost:8080",
      now: now,
    )

  let assert Error(_) =
    auth.validate_access_token(
      session_secret: secret,
      token: token,
      resource: "http://evil.com",
      now: now,
    )
}

pub fn should_reject_expired_access_token_test() {
  let secret = "test-secret"
  let now = 1_000_000
  let token =
    auth.create_access_token(
      session_secret: secret,
      user_id: 42,
      resource: "http://localhost:8080",
      now: now,
    )

  // 2 hours later — 1-hour TTL
  let assert Error(_) =
    auth.validate_access_token(
      session_secret: secret,
      token: token,
      resource: "http://localhost:8080",
      now: now + 7200,
    )
}

pub fn should_generate_refresh_token_test() {
  let token1 = auth.generate_refresh_token()
  let token2 = auth.generate_refresh_token()
  // 64 hex chars (32 bytes)
  assert string.length(token1) == 64
  assert token1 != token2
}
