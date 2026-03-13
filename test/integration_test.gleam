import gleam/http
import gleam/json
import gleam/list
import gleam/string

import gleam_mcp_todo/auth
import gleam_mcp_todo/context.{type Context}
import gleam_mcp_todo/time
import support/test_helpers
import wisp.{type Response}
import wisp/simulate

/// Get an access token for a test user
fn get_access_token(context: Context) -> String {
  let now = time.now_unix()
  let assert Ok(user) =
    auth.auto_login(conn: context.db, email: "test@example.com", now: now)

  auth.create_access_token(
    session_secret: test_helpers.secret(),
    user_id: user.id,
    resource: test_helpers.test_resource,
    now: now,
  )
}

/// Send an MCP JSON-RPC request
fn mcp_request(
  method method: String,
  params params: json.Json,
  bearer bearer: String,
  session_id session_id: String,
) {
  let req =
    simulate.request(http.Post, "/")
    |> simulate.header("content-type", "application/json")
    |> simulate.header("accept", "application/json, text/event-stream")
    |> simulate.header("authorization", "Bearer " <> bearer)

  let req = case session_id {
    "" -> req
    sid -> simulate.header(req, "mcp-session-id", sid)
  }

  let body = case method {
    "notifications/initialized" ->
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("method", json.string(method)),
      ])
    _ ->
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", json.int(1)),
        #("method", json.string(method)),
        #("params", params),
      ])
  }

  simulate.json_body(req, body)
}

/// Extract session ID from response headers
fn get_session_id(response: Response) -> String {
  case list.key_find(response.headers, "mcp-session-id") {
    Ok(value) -> value
    Error(_) -> ""
  }
}

// --- Full MCP Flow Test ---

pub fn full_mcp_flow_test() {
  let context = test_helpers.setup()
  let token = get_access_token(context)

  // 1. Initialize
  let init_response =
    mcp_request(
      method: "initialize",
      params: json.object([]),
      bearer: token,
      session_id: "",
    )
    |> test_helpers.handle(context: context)

  assert init_response.status == 200
  let session_id = get_session_id(init_response)
  assert string.length(session_id) > 0

  let body = simulate.read_body(init_response)
  assert string.contains(body, "protocolVersion")

  // 2. Initialized notification
  let notif_response =
    mcp_request(
      method: "notifications/initialized",
      params: json.object([]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert notif_response.status == 202

  // 3. Tools list
  let tools_response =
    mcp_request(
      method: "tools/list",
      params: json.object([]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert tools_response.status == 200
  let tools_body = simulate.read_body(tools_response)
  assert string.contains(tools_body, "list_todos")
  assert string.contains(tools_body, "create_todo")
  assert string.contains(tools_body, "get_todo")
  assert string.contains(tools_body, "update_todo")
  assert string.contains(tools_body, "complete_todo")
  assert string.contains(tools_body, "delete_todo")

  // 4. Create a todo
  let create_response =
    mcp_request(
      method: "tools/call",
      params: json.object([
        #("name", json.string("create_todo")),
        #("arguments", json.object([#("title", json.string("Buy milk"))])),
      ]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert create_response.status == 200
  let create_body = simulate.read_body(create_response)
  assert string.contains(create_body, "Todo created")
  assert string.contains(create_body, "Buy milk")

  // 5. List todos — should show 1 todo
  let list_response =
    mcp_request(
      method: "tools/call",
      params: json.object([
        #("name", json.string("list_todos")),
        #("arguments", json.object([])),
      ]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert list_response.status == 200
  let list_body = simulate.read_body(list_response)
  assert string.contains(list_body, "You have 1 todo")
  assert string.contains(list_body, "Buy milk")

  // 6. Get the todo
  let get_response =
    mcp_request(
      method: "tools/call",
      params: json.object([
        #("name", json.string("get_todo")),
        #("arguments", json.object([#("todo_id", json.int(1))])),
      ]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert get_response.status == 200
  let get_body = simulate.read_body(get_response)
  assert string.contains(get_body, "Buy milk")
  assert string.contains(get_body, "incomplete")

  // 7. Complete the todo
  let complete_response =
    mcp_request(
      method: "tools/call",
      params: json.object([
        #("name", json.string("complete_todo")),
        #("arguments", json.object([#("todo_id", json.int(1))])),
      ]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert complete_response.status == 200
  let complete_body = simulate.read_body(complete_response)
  assert string.contains(complete_body, "marked complete")

  // 8. Update the todo
  let update_response =
    mcp_request(
      method: "tools/call",
      params: json.object([
        #("name", json.string("update_todo")),
        #(
          "arguments",
          json.object([
            #("todo_id", json.int(1)),
            #("title", json.string("Buy oat milk")),
          ]),
        ),
      ]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert update_response.status == 200
  let update_body = simulate.read_body(update_response)
  assert string.contains(update_body, "Todo updated")
  assert string.contains(update_body, "Buy oat milk")

  // 9. Delete the todo
  let delete_response =
    mcp_request(
      method: "tools/call",
      params: json.object([
        #("name", json.string("delete_todo")),
        #("arguments", json.object([#("todo_id", json.int(1))])),
      ]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert delete_response.status == 200
  let delete_body = simulate.read_body(delete_response)
  assert string.contains(delete_body, "deleted")

  // 10. List todos — should be empty
  let final_response =
    mcp_request(
      method: "tools/call",
      params: json.object([
        #("name", json.string("list_todos")),
        #("arguments", json.object([])),
      ]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert final_response.status == 200
  let final_body = simulate.read_body(final_response)
  assert string.contains(final_body, "no todos")
}

// --- Session Tests ---

pub fn invalid_session_returns_404_test() {
  let context = test_helpers.setup()
  let token = get_access_token(context)

  let response =
    mcp_request(
      method: "tools/list",
      params: json.object([]),
      bearer: token,
      session_id: "invalid-session-id",
    )
    |> test_helpers.handle(context: context)

  assert response.status == 404
}

pub fn delete_session_test() {
  let context = test_helpers.setup()
  let token = get_access_token(context)

  // Initialize to get a session
  let init_response =
    mcp_request(
      method: "initialize",
      params: json.object([]),
      bearer: token,
      session_id: "",
    )
    |> test_helpers.handle(context: context)

  let session_id = get_session_id(init_response)

  // Delete session
  let delete_response =
    simulate.request(http.Delete, "/")
    |> simulate.header("mcp-session-id", session_id)
    |> test_helpers.handle(context: context)

  assert delete_response.status == 204

  // Subsequent request should get 404
  let response =
    mcp_request(
      method: "tools/list",
      params: json.object([]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert response.status == 404
}

// --- Ping ---

pub fn ping_test() {
  let context = test_helpers.setup()
  let token = get_access_token(context)

  let init_response =
    mcp_request(
      method: "initialize",
      params: json.object([]),
      bearer: token,
      session_id: "",
    )
    |> test_helpers.handle(context: context)

  let session_id = get_session_id(init_response)

  let response =
    mcp_request(
      method: "ping",
      params: json.object([]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert response.status == 200
  let body = simulate.read_body(response)
  assert string.contains(body, "\"result\"")
}

// --- Unknown Method ---

pub fn unknown_method_test() {
  let context = test_helpers.setup()
  let token = get_access_token(context)

  let init_response =
    mcp_request(
      method: "initialize",
      params: json.object([]),
      bearer: token,
      session_id: "",
    )
    |> test_helpers.handle(context: context)

  let session_id = get_session_id(init_response)

  let response =
    mcp_request(
      method: "nonexistent/method",
      params: json.object([]),
      bearer: token,
      session_id: session_id,
    )
    |> test_helpers.handle(context: context)

  assert response.status == 400
  let body = simulate.read_body(response)
  assert string.contains(body, "Method not found")
}
