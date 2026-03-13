import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import gleam_mcp_todo/db
import gleam_mcp_todo/sql
import sqlight

// --- Types ---

pub type AuthError {
  InvalidToken
  SupersededToken
  ExpiredToken
  DatabaseError(sqlight.Error)
}

pub type LoginRequest {
  LoginRequest(token: String, email: String)
}

/// Domain type decoupled from Parrot-generated query types (e.g. sql.GetUserById,
/// sql.CreateUser) so callers don't depend on a specific SQL query shape.
pub type User {
  User(id: Int, email: String, created_at: Int, updated_at: Int)
}

// --- Constants ---

const verification_token_ttl = 3600

const unambiguous_alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

// --- Access Tokens (Resource-bound, 1-hour TTL) ---

pub const access_token_ttl = 3600

pub fn create_access_token(
  session_secret session_secret: String,
  user_id user_id: Int,
  resource resource: String,
  now now: Int,
) -> String {
  let expires_at = now + access_token_ttl
  let resource_hash = hash_short(resource)
  create_hmac_token(secret: session_secret, prefix: "access", fields: [
    int.to_string(user_id),
    resource_hash,
    int.to_string(expires_at),
  ])
}

pub fn validate_access_token(
  session_secret session_secret: String,
  token token: String,
  resource resource: String,
  now now: Int,
) -> Result(Int, AuthError) {
  use parts <- validate_hmac_token(
    secret: session_secret,
    token: token,
    prefix: "access",
    expected_parts: 3,
  )
  case parts {
    [user_id_str, resource_hash, expires_at_str] -> {
      use user_id <- result.try(
        int.parse(user_id_str) |> result.replace_error(InvalidToken),
      )
      use expires_at <- result.try(
        int.parse(expires_at_str) |> result.replace_error(InvalidToken),
      )
      use <- bool.guard(when: expires_at <= now, return: Error(ExpiredToken))
      let expected_resource_hash = hash_short(resource)
      use <- bool.guard(
        when: resource_hash != expected_resource_hash,
        return: Error(InvalidToken),
      )
      Ok(user_id)
    }
    _ -> Error(InvalidToken)
  }
}

fn hash_short(value: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(value))
  |> hex_encode
  |> string.slice(0, 8)
}

// --- Refresh Tokens ---

// 30 days — refresh tokens expire after 30 days
const refresh_token_ttl = 2_592_000

pub fn random_hex(bytes bytes: Int) -> String {
  crypto.strong_random_bytes(bytes)
  |> hex_encode
}

pub fn generate_refresh_token() -> String {
  random_hex(bytes: 32)
}

pub fn refresh_token_expires_at(now now: Int) -> Int {
  now + refresh_token_ttl
}

// --- Verification Tokens ---

pub fn generate_verification_code() -> String {
  let bytes = crypto.strong_random_bytes(5)
  let alphabet = string.to_graphemes(unambiguous_alphabet)
  let alphabet_len = list.length(alphabet)

  bytes_to_list(bytes)
  |> list.map(fn(byte) {
    let index = byte % alphabet_len
    case list.drop(alphabet, index) {
      [char, ..] -> char
      [] -> "X"
    }
  })
  |> string.join("")
}

fn bytes_to_list(bits: BitArray) -> List(Int) {
  case bits {
    <<byte:int, rest:bits>> -> [byte, ..bytes_to_list(rest)]
    _ -> []
  }
}

pub fn hash_token(email email: String, token token: String) -> String {
  let input = email <> ":" <> string.uppercase(token)
  crypto.hash(crypto.Sha256, bit_array.from_string(input))
  |> hex_encode
}

pub fn hash_refresh_token(token token: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(token))
  |> hex_encode
}

// --- Login Flow ---

pub fn request_login(
  conn conn: sqlight.Connection,
  email email: String,
  now now: Int,
) -> Result(LoginRequest, AuthError) {
  let email = string.lowercase(string.trim(email))
  let token = generate_verification_code()
  let token_hash = hash_token(email: email, token: token)
  let expires_at = now + verification_token_ttl

  use _user_id <- result.try(ensure_user_email(
    conn: conn,
    email: email,
    now: now,
  ))

  // Set verification token
  case
    db.exec(
      conn: conn,
      query: sql.set_verification_token(
        token_hash: Some(token_hash),
        token_expires_at: Some(expires_at),
        email: email,
      ),
    )
  {
    Ok(Nil) -> Ok(LoginRequest(token: token, email: email))
    Error(err) -> Error(DatabaseError(err))
  }
}

pub fn verify_login(
  conn conn: sqlight.Connection,
  email email: String,
  token token: String,
  now now: Int,
) -> Result(User, AuthError) {
  let email = string.lowercase(string.trim(email))
  let submitted_hash = hash_token(email: email, token: token)

  use row <- result.try(
    db.query_one(conn: conn, query: sql.get_user_email_by_email(email: email))
    |> result.map_error(DatabaseError)
    |> result.try(fn(opt) { option.to_result(opt, InvalidToken) }),
  )

  use stored_hash <- result.try(option.to_result(row.token_hash, InvalidToken))

  let matches_current =
    crypto.secure_compare(
      bit_array.from_string(submitted_hash),
      bit_array.from_string(stored_hash),
    )

  case matches_current {
    True -> {
      case row.token_expires_at {
        Some(expires_at) if expires_at > now ->
          complete_verification(
            conn: conn,
            email: email,
            user_id: row.user_id,
            now: now,
          )
        _ -> Error(ExpiredToken)
      }
    }
    False ->
      check_previous_hash(
        previous_hash: row.previous_token_hash,
        submitted_hash: submitted_hash,
      )
  }
}

// --- Auto Login (skips verification code, used by tests) ---
// Note: does not clear pending verification tokens on the user_email row.
// This is fine for test-only use but should not be used in production paths.

pub fn auto_login(
  conn conn: sqlight.Connection,
  email email: String,
  now now: Int,
) -> Result(User, AuthError) {
  let email = string.lowercase(string.trim(email))

  use user_id <- result.try(ensure_user_email(
    conn: conn,
    email: email,
    now: now,
  ))

  case user_id {
    Some(id) -> get_user(conn: conn, id: id)
    None -> create_and_link_user(conn: conn, email: email, now: now)
  }
}

// --- Internal Helpers ---

/// Returns Some(user_id) if the email is already linked to a user, or None if
/// the email exists without a linked user OR was just created. In the login
/// flow, None means the caller must create a new user after verification.
fn ensure_user_email(
  conn conn: sqlight.Connection,
  email email: String,
  now now: Int,
) -> Result(Option(Int), AuthError) {
  use result <- result.try(
    db.query_one(conn: conn, query: sql.get_user_email_by_email(email: email))
    |> result.map_error(DatabaseError),
  )
  case result {
    Some(row) -> Ok(row.user_id)
    None -> {
      use _ <- result.try(
        db.query_one(
          conn: conn,
          query: sql.create_user_email(email: email, created_at: now),
        )
        |> result.map_error(DatabaseError),
      )
      Ok(None)
    }
  }
}

fn check_previous_hash(
  previous_hash previous_hash: Option(String),
  submitted_hash submitted_hash: String,
) -> Result(User, AuthError) {
  case previous_hash {
    Some(prev_hash) ->
      case
        crypto.secure_compare(
          bit_array.from_string(submitted_hash),
          bit_array.from_string(prev_hash),
        )
      {
        True -> Error(SupersededToken)
        False -> Error(InvalidToken)
      }
    None -> Error(InvalidToken)
  }
}

fn create_and_link_user(
  conn conn: sqlight.Connection,
  email email: String,
  now now: Int,
) -> Result(User, AuthError) {
  use result <- result.try(
    db.query_one(
      conn: conn,
      query: sql.create_user(email: email, created_at: now, updated_at: now),
    )
    |> result.map_error(DatabaseError),
  )
  use user_row <- result.try(option.to_result(result, InvalidToken))
  use _ <- result.try(
    db.exec(
      conn: conn,
      query: sql.claim_user_email(user_id: Some(user_row.id), email: email),
    )
    |> result.map_error(DatabaseError),
  )
  Ok(User(
    id: user_row.id,
    email: user_row.email,
    created_at: user_row.created_at,
    updated_at: user_row.updated_at,
  ))
}

fn user_from_row(row: sql.GetUserById) -> User {
  User(
    id: row.id,
    email: row.email,
    created_at: row.created_at,
    updated_at: row.updated_at,
  )
}

fn get_user(
  conn conn: sqlight.Connection,
  id id: Int,
) -> Result(User, AuthError) {
  case db.query_one(conn: conn, query: sql.get_user_by_id(id: id)) {
    Ok(Some(row)) -> Ok(user_from_row(row))
    Ok(None) -> Error(InvalidToken)
    Error(err) -> Error(DatabaseError(err))
  }
}

fn complete_verification(
  conn conn: sqlight.Connection,
  email email: String,
  user_id user_id: Option(Int),
  now now: Int,
) -> Result(User, AuthError) {
  use _ <- result.try(
    db.exec(
      conn: conn,
      query: sql.verify_user_email(verified_at: Some(now), email: email),
    )
    |> result.map_error(DatabaseError),
  )
  case user_id {
    Some(id) -> get_user(conn: conn, id: id)
    None -> create_and_link_user(conn: conn, email: email, now: now)
  }
}

fn create_hmac_token(
  secret secret: String,
  prefix prefix: String,
  fields fields: List(String),
) -> String {
  let payload = prefix <> ":" <> string.join(fields, ":")
  let hmac = compute_hmac(secret: secret, payload: payload)
  string.join(fields, ".") <> "." <> hmac
}

fn validate_hmac_token(
  secret secret: String,
  token token: String,
  prefix prefix: String,
  expected_parts expected_parts: Int,
  next next: fn(List(String)) -> Result(Int, AuthError),
) -> Result(Int, AuthError) {
  let parts = string.split(token, ".")
  let parts_count = list.length(parts)
  use <- bool.guard(
    when: parts_count != expected_parts + 1,
    return: Error(InvalidToken),
  )
  let fields = list.take(parts, expected_parts)
  let hmac = list.drop(parts, expected_parts)
  case hmac {
    [hmac_value] -> {
      let payload = prefix <> ":" <> string.join(fields, ":")
      let expected = compute_hmac(secret: secret, payload: payload)
      case
        crypto.secure_compare(
          bit_array.from_string(hmac_value),
          bit_array.from_string(expected),
        )
      {
        True -> next(fields)
        False -> Error(InvalidToken)
      }
    }
    _ -> Error(InvalidToken)
  }
}

fn compute_hmac(secret secret: String, payload payload: String) -> String {
  crypto.hmac(
    bit_array.from_string(payload),
    crypto.Sha256,
    bit_array.from_string(secret),
  )
  |> hex_encode
}

fn hex_encode(bytes: BitArray) -> String {
  bytes
  |> bit_array.base16_encode
  |> string.lowercase
}
