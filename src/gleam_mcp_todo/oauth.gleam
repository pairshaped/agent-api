import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

import logging

import gleam_mcp_todo/auth
import gleam_mcp_todo/context.{type Context}
import gleam_mcp_todo/db
import gleam_mcp_todo/mcp
import gleam_mcp_todo/sql
import gleam_mcp_todo/time
import wisp.{type Request, type Response}

// --- Constants ---

const code_ttl = 600

// --- Well-Known Endpoints ---

pub fn protected_resource_metadata(resource resource: String) -> Response {
  let body =
    json.object([
      #("resource", json.string(resource)),
      #(
        "authorization_servers",
        json.preprocessed_array([json.string(resource)]),
      ),
      #("scopes_supported", json.preprocessed_array([])),
      #(
        "bearer_methods_supported",
        json.preprocessed_array([json.string("header")]),
      ),
    ])
    |> json.to_string()
  mcp.json_response(body: body, status: 200)
}

pub fn authorization_server_metadata(resource resource: String) -> Response {
  let body =
    json.object([
      #("issuer", json.string(resource)),
      #("authorization_endpoint", json.string(resource <> "/oauth/authorize")),
      #("token_endpoint", json.string(resource <> "/oauth/token")),
      #("registration_endpoint", json.string(resource <> "/oauth/register")),
      #("revocation_endpoint", json.string(resource <> "/oauth/revoke")),
      #(
        "response_types_supported",
        json.preprocessed_array([json.string("code")]),
      ),
      #(
        "code_challenge_methods_supported",
        json.preprocessed_array([json.string("S256")]),
      ),
      #(
        "token_endpoint_auth_methods_supported",
        json.preprocessed_array([
          json.string("none"),
        ]),
      ),
      #(
        "grant_types_supported",
        json.preprocessed_array([
          json.string("authorization_code"),
          json.string("refresh_token"),
        ]),
      ),
      #("scopes_supported", json.preprocessed_array([])),
    ])
    |> json.to_string()
  mcp.json_response(body: body, status: 200)
}

// --- Dynamic Client Registration (RFC 7591) ---

pub fn handle_register(
  request request: Request,
  context context: Context,
) -> Response {
  use json_body <- wisp.require_json(request)

  let decoder = {
    use redirect_uris <- decode.field(
      "redirect_uris",
      decode.list(decode.string),
    )
    use client_name <- decode.optional_field(
      "client_name",
      "MCP Client",
      decode.string,
    )
    decode.success(#(redirect_uris, client_name))
  }

  case decode.run(json_body, decoder) {
    Error(_) ->
      mcp.json_error(status: 400, message: "Invalid registration request")
    Ok(#(redirect_uris, client_name)) -> {
      use <- bool.guard(
        when: list.is_empty(redirect_uris),
        return: mcp.json_error(
          status: 400,
          message: "At least one redirect_uri is required",
        ),
      )
      let client_id = generate_client_id()
      let redirect_uris_json =
        json.array(redirect_uris, json.string)
        |> json.to_string()
      let now = time.now_unix()

      case
        db.exec(
          conn: context.db,
          query: sql.create_oauth_client(
            client_id: client_id,
            client_secret_hash: None,
            client_secret_expires_at: 0,
            redirect_uris: redirect_uris_json,
            client_name: client_name,
            token_endpoint_auth_method: "none",
            created_at: now,
          ),
        )
      {
        Ok(Nil) -> {
          let body =
            json.object([
              #("client_id", json.string(client_id)),
              #("client_name", json.string(client_name)),
              #("redirect_uris", json.array(redirect_uris, json.string)),
              #("token_endpoint_auth_method", json.string("none")),
            ])
            |> json.to_string()
          mcp.json_response(body: body, status: 201)
        }
        Error(_) ->
          mcp.json_error(status: 500, message: "Failed to register client")
      }
    }
  }
}

// --- Token Endpoint ---

pub fn handle_token(
  request request: Request,
  context context: Context,
) -> Response {
  use form_data <- wisp.require_form(request)
  let fields = form_data.values

  case list.key_find(fields, "grant_type") {
    Error(_) -> mcp.json_error(status: 400, message: "Missing grant_type")
    Ok("authorization_code") ->
      handle_authorization_code_grant(fields: fields, context: context)
    Ok("refresh_token") ->
      handle_refresh_token_grant(fields: fields, context: context)
    Ok(_) -> mcp.json_error(status: 400, message: "Unsupported grant_type")
  }
}

fn handle_authorization_code_grant(
  fields fields: List(#(String, String)),
  context context: Context,
) -> Response {
  let find = require_field(fields: fields, key: _)
  let result = {
    use code <- result.try(find("code"))
    use code_verifier <- result.try(find("code_verifier"))
    use redirect_uri <- result.try(find("redirect_uri"))
    use client_id <- result.try(find("client_id"))
    use resource <- result.try(find("resource"))
    Ok(#(code, code_verifier, redirect_uri, client_id, resource))
  }

  case result {
    Error(message) -> mcp.json_error(status: 400, message: message)
    Ok(#(code, code_verifier, redirect_uri, client_id, resource)) -> {
      let now = time.now_unix()
      case
        db.query_one(
          conn: context.db,
          query: sql.get_authorization_code(code: code),
        )
      {
        Ok(Some(auth_code)) ->
          exchange_authorization_code(
            context: context,
            auth_code: auth_code,
            code: code,
            code_verifier: code_verifier,
            redirect_uri: redirect_uri,
            client_id: client_id,
            resource: resource,
            now: now,
          )
        _ -> mcp.json_error(status: 400, message: "Invalid authorization code")
      }
    }
  }
}

fn exchange_authorization_code(
  context context: Context,
  auth_code auth_code: sql.GetAuthorizationCode,
  code code: String,
  code_verifier code_verifier: String,
  redirect_uri redirect_uri: String,
  client_id client_id: String,
  resource resource: String,
  now now: Int,
) -> Response {
  // Delete the code first (single use) — must succeed to prevent replay
  case
    db.exec(conn: context.db, query: sql.delete_authorization_code(code: code))
  {
    Error(_) ->
      mcp.json_error(
        status: 500,
        message: "Failed to consume authorization code",
      )
    Ok(Nil) -> {
      // Validate
      use <- bool.guard(
        when: auth_code.expires_at <= now,
        return: mcp.json_error(
          status: 400,
          message: "Authorization code expired",
        ),
      )
      use <- bool.guard(
        when: auth_code.client_id != client_id,
        return: mcp.json_error(status: 400, message: "Client ID mismatch"),
      )
      use <- bool.guard(
        when: auth_code.redirect_uri != redirect_uri,
        return: mcp.json_error(status: 400, message: "Redirect URI mismatch"),
      )
      use <- bool.guard(
        when: !validate_pkce(
          code_verifier: code_verifier,
          code_challenge: auth_code.code_challenge,
        ),
        return: mcp.json_error(status: 400, message: "Invalid code_verifier"),
      )
      use <- bool.guard(
        when: resource != auth_code.resource,
        return: {
          logging.log(
            logging.Error,
            "Resource mismatch: client sent '"
              <> resource
              <> "' but auth code has '"
              <> auth_code.resource
              <> "'",
          )
          mcp.json_error(status: 400, message: "Resource mismatch")
        },
      )
      issue_tokens(
        context: context,
        user_id: auth_code.user_id,
        client_id: client_id,
        resource: auth_code.resource,
        scope: auth_code.scope,
        now: now,
      )
    }
  }
}

fn handle_refresh_token_grant(
  fields fields: List(#(String, String)),
  context context: Context,
) -> Response {
  let find = require_field(fields: fields, key: _)
  let result = {
    use refresh_token <- result.try(find("refresh_token"))
    use client_id <- result.try(find("client_id"))
    Ok(#(refresh_token, client_id))
  }

  case result {
    Error(message) -> mcp.json_error(status: 400, message: message)
    Ok(#(refresh_token, client_id)) -> {
      let now = time.now_unix()
      let token_hash = auth.hash_refresh_token(token: refresh_token)
      case
        db.query_one(
          conn: context.db,
          query: sql.get_refresh_token(token_hash: token_hash),
        )
      {
        Ok(Some(stored)) ->
          rotate_refresh_token(
            context: context,
            stored: stored,
            token_hash: token_hash,
            client_id: client_id,
            now: now,
          )
        _ -> mcp.json_error(status: 400, message: "Invalid refresh token")
      }
    }
  }
}

fn rotate_refresh_token(
  context context: Context,
  stored stored: sql.GetRefreshToken,
  token_hash token_hash: String,
  client_id client_id: String,
  now now: Int,
) -> Response {
  use <- bool.guard(
    when: option.is_some(stored.revoked_at),
    return: mcp.json_error(status: 400, message: "Refresh token revoked"),
  )
  use <- bool.guard(
    when: stored.expires_at <= now,
    return: mcp.json_error(status: 400, message: "Refresh token expired"),
  )
  use <- bool.guard(
    when: stored.client_id != client_id,
    return: mcp.json_error(status: 400, message: "Client ID mismatch"),
  )

  // Revoke old token (after validation passes)
  db.exec_or_log(
    conn: context.db,
    query: sql.revoke_refresh_token(
      revoked_at: Some(now),
      token_hash: token_hash,
    ),
    label: "Failed to revoke refresh token",
  )

  issue_tokens(
    context: context,
    user_id: stored.user_id,
    client_id: client_id,
    resource: stored.resource,
    scope: stored.scope,
    now: now,
  )
}

fn issue_tokens(
  context context: Context,
  user_id user_id: Int,
  client_id client_id: String,
  resource resource: String,
  scope scope: String,
  now now: Int,
) -> Response {
  let access_token =
    auth.create_access_token(
      session_secret: context.session_secret,
      user_id: user_id,
      resource: resource,
      now: now,
    )

  let refresh_token = auth.generate_refresh_token()
  let refresh_hash = auth.hash_refresh_token(token: refresh_token)
  let refresh_expires = auth.refresh_token_expires_at(now: now)

  case
    db.exec(
      conn: context.db,
      query: sql.create_refresh_token(
        token_hash: refresh_hash,
        client_id: client_id,
        user_id: user_id,
        resource: resource,
        scope: scope,
        expires_at: refresh_expires,
        created_at: now,
      ),
    )
  {
    Ok(Nil) -> {
      let body =
        json.object([
          #("access_token", json.string(access_token)),
          #("token_type", json.string("bearer")),
          #("expires_in", json.int(auth.access_token_ttl)),
          #("refresh_token", json.string(refresh_token)),
        ])
        |> json.to_string()
      mcp.json_response(body: body, status: 200)
      |> wisp.set_header("cache-control", "no-store")
    }
    Error(_) -> mcp.json_error(status: 500, message: "Failed to issue tokens")
  }
}

// --- Revocation ---

pub fn handle_revoke(
  request request: Request,
  context context: Context,
) -> Response {
  use form_data <- wisp.require_form(request)
  let fields = form_data.values

  case list.key_find(fields, "token") {
    Error(_) -> mcp.json_error(status: 400, message: "Missing token")
    Ok(token) -> {
      let token_hash = auth.hash_refresh_token(token: token)
      let now = time.now_unix()
      // RFC 7009 requires 200 regardless of whether revocation succeeded
      db.exec_or_log(
        conn: context.db,
        query: sql.revoke_refresh_token(
          revoked_at: Some(now),
          token_hash: token_hash,
        ),
        label: "Token revocation failed",
      )
      wisp.response(200)
    }
  }
}

// --- Authorization Code Generation ---

pub fn create_authorization_code(
  context context: Context,
  client_id client_id: String,
  user_id user_id: Int,
  redirect_uri redirect_uri: String,
  code_challenge code_challenge: String,
  resource resource: String,
  scope scope: String,
) -> Result(String, Nil) {
  let code = generate_code()
  let now = time.now_unix()
  let expires_at = now + code_ttl

  case
    db.exec(
      conn: context.db,
      query: sql.create_authorization_code(
        code: code,
        client_id: client_id,
        user_id: user_id,
        redirect_uri: redirect_uri,
        code_challenge: code_challenge,
        resource: resource,
        scope: scope,
        expires_at: expires_at,
        created_at: now,
      ),
    )
  {
    Ok(Nil) -> Ok(code)
    Error(_) -> Error(Nil)
  }
}

// --- PKCE ---

fn validate_pkce(
  code_verifier code_verifier: String,
  code_challenge code_challenge: String,
) -> Bool {
  // S256: BASE64URL(SHA256(code_verifier))
  let computed =
    crypto.hash(crypto.Sha256, bit_array.from_string(code_verifier))
    |> base64_url_encode
  crypto.secure_compare(
    bit_array.from_string(computed),
    bit_array.from_string(code_challenge),
  )
}

fn base64_url_encode(bytes: BitArray) -> String {
  bit_array.base64_encode(bytes, False)
  |> string.replace("+", "-")
  |> string.replace("/", "_")
  |> string.replace("=", "")
}

// --- Validate Client ---

pub fn validate_client(
  context context: context.Context,
  client_id client_id: String,
  redirect_uri redirect_uri: String,
) -> Result(sql.GetOauthClient, Nil) {
  case
    db.query_one(
      conn: context.db,
      query: sql.get_oauth_client(client_id: client_id),
    )
  {
    Ok(Some(client)) -> {
      // Parse the stored JSON array and check for exact match
      let uris_decoder = decode.list(decode.string)
      case json.parse(from: client.redirect_uris, using: uris_decoder) {
        Ok(uris) ->
          case list.contains(uris, redirect_uri) {
            True -> Ok(client)
            False -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

// --- Helpers ---

fn require_field(
  fields fields: List(#(String, String)),
  key key: String,
) -> Result(String, String) {
  list.key_find(fields, key)
  |> result.replace_error("Missing required parameter: " <> key)
}

fn generate_client_id() -> String {
  auth.random_hex(bytes: 16)
}

fn generate_code() -> String {
  auth.random_hex(bytes: 32)
}
