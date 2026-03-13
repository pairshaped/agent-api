import gleam/http
import gleam/json
import gleam/string

import gleam_mcp_todo/auth
import gleam_mcp_todo/time
import support/test_helpers
import wisp/simulate

// --- Protected Resource Metadata ---

pub fn protected_resource_metadata_test() {
  let context = test_helpers.setup()
  let response =
    simulate.request(http.Get, "/.well-known/oauth-protected-resource")
    |> test_helpers.handle(context: context)

  assert response.status == 200
  let assert Ok(resource) =
    test_helpers.read_json_field(response: response, field_name: "resource")
  assert resource == test_helpers.test_resource
}

// --- Authorization Server Metadata ---

pub fn authorization_server_metadata_test() {
  let context = test_helpers.setup()
  let response =
    simulate.request(http.Get, "/.well-known/oauth-authorization-server")
    |> test_helpers.handle(context: context)

  assert response.status == 200
  let assert Ok(issuer) =
    test_helpers.read_json_field(response: response, field_name: "issuer")
  assert issuer == test_helpers.test_resource
  let assert Ok(auth_endpoint) =
    test_helpers.read_json_field(
      response: response,
      field_name: "authorization_endpoint",
    )
  assert string.contains(auth_endpoint, "/oauth/authorize")
}

// --- Dynamic Client Registration ---

pub fn register_client_test() {
  let context = test_helpers.setup()
  let response =
    simulate.request(http.Post, "/oauth/register")
    |> simulate.json_body(
      json.object([
        #(
          "redirect_uris",
          json.preprocessed_array([
            json.string("http://localhost:3000/callback"),
          ]),
        ),
        #("client_name", json.string("Test Client")),
      ]),
    )
    |> test_helpers.handle(context: context)

  assert response.status == 201
  let assert Ok(client_id) =
    test_helpers.read_json_field(response: response, field_name: "client_id")
  assert string.length(client_id) > 0
  let assert Ok(name) =
    test_helpers.read_json_field(response: response, field_name: "client_name")
  assert name == "Test Client"
}

pub fn register_client_missing_redirect_uris_test() {
  let context = test_helpers.setup()
  let response =
    simulate.request(http.Post, "/oauth/register")
    |> simulate.json_body(json.object([#("client_name", json.string("Test"))]))
    |> test_helpers.handle(context: context)

  assert response.status == 400
}

// --- MCP POST without auth returns 401 ---

pub fn mcp_post_without_auth_returns_401_test() {
  let context = test_helpers.setup()
  let response =
    simulate.request(http.Post, "/")
    |> simulate.header("content-type", "application/json")
    |> simulate.header("accept", "application/json, text/event-stream")
    |> simulate.json_body(
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", json.int(1)),
        #("method", json.string("initialize")),
        #("params", json.object([])),
      ]),
    )
    |> test_helpers.handle(context: context)

  assert response.status == 401
}

// --- MCP Initialize with valid access token ---

pub fn mcp_initialize_with_access_token_test() {
  let context = test_helpers.setup()

  // Create a test user and get an access token
  let now = time.now_unix()
  let assert Ok(user) =
    auth.auto_login(conn: context.db, email: "test@example.com", now: now)

  let token =
    auth.create_access_token(
      session_secret: test_helpers.secret(),
      user_id: user.id,
      resource: test_helpers.test_resource,
      now: now,
    )

  let response =
    simulate.request(http.Post, "/")
    |> simulate.header("content-type", "application/json")
    |> simulate.header("accept", "application/json, text/event-stream")
    |> simulate.header("authorization", "Bearer " <> token)
    |> simulate.json_body(
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", json.int(1)),
        #("method", json.string("initialize")),
        #("params", json.object([])),
      ]),
    )
    |> test_helpers.handle(context: context)

  assert response.status == 200
  let body = simulate.read_body(response)
  assert string.contains(body, "protocolVersion")
  assert string.contains(body, "capabilities")
  assert string.contains(body, "serverInfo")
}

// --- Setup page ---

pub fn setup_page_returns_html_test() {
  let context = test_helpers.setup()
  let response =
    simulate.request(http.Get, "/")
    |> simulate.header("accept", "text/html")
    |> test_helpers.handle(context: context)

  assert response.status == 200
  let body = simulate.read_body(response)
  assert string.contains(body, "Todo List MCP Server Setup")
}

// --- Token endpoint ---

pub fn token_endpoint_invalid_grant_type_test() {
  let context = test_helpers.setup()
  let response =
    simulate.request(http.Post, "/oauth/token")
    |> simulate.form_body([#("grant_type", "password")])
    |> test_helpers.handle(context: context)

  assert response.status == 400
}

// --- Revocation ---

pub fn revoke_returns_200_test() {
  let context = test_helpers.setup()
  let response =
    simulate.request(http.Post, "/oauth/revoke")
    |> simulate.form_body([#("token", "nonexistent-token")])
    |> test_helpers.handle(context: context)

  // Always returns 200 per RFC 7009
  assert response.status == 200
}
