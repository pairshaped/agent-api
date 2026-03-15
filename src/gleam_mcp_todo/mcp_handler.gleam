import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import logging

import gleam_mcp_todo/auth
import gleam_mcp_todo/context.{type Context}
import gleam_mcp_todo/db
import gleam_mcp_todo/mcp
import gleam_mcp_todo/mcp_tools
import gleam_mcp_todo/sql
import gleam_mcp_todo/time
import sqlight
import wisp.{type Request, type Response}

// --- Main Handler ---

pub fn handle_post(
  request request: Request,
  context context: Context,
  session_id session_id: Option(String),
  user_id user_id: Int,
) -> Response {
  use json_body <- wisp.require_json(request)

  case mcp.parse_message(json_body) {
    Error(error) -> {
      let body = mcp.error_response(None, error, "Invalid JSON-RPC message")
      mcp.json_response(body: body, status: 400)
    }
    Ok(mcp.McpNotification(method: method, ..)) ->
      handle_notification(method: method)
    Ok(mcp.McpRequest(id: id, method: method, params: params)) ->
      handle_request(
        id: id,
        method: method,
        params: params,
        context: context,
        session_id: session_id,
        user_id: user_id,
      )
  }
}

/// Handle initialize — no session required yet
pub fn handle_initialize_post(
  request request: Request,
  context context: Context,
  user_id user_id: Int,
) -> Response {
  use json_body <- wisp.require_json(request)

  case mcp.parse_message(json_body) {
    Error(error) -> {
      let body = mcp.error_response(None, error, "Invalid JSON-RPC message")
      mcp.json_response(body: body, status: 400)
    }
    Ok(mcp.McpRequest(id: id, method: "initialize", params: _params)) -> {
      // Generate session ID
      let session_id = generate_session_id()
      let now = time.now_unix()

      // Store session
      case
        db.exec(
          conn: context.db,
          query: sql.create_mcp_session(
            session_id: session_id,
            user_id: user_id,
            created_at: now,
            last_seen_at: now,
          ),
        )
      {
        Ok(Nil) -> {
          let result =
            json.object([
              #("protocolVersion", json.string(mcp.protocol_version)),
              #("capabilities", mcp.server_capabilities()),
              #("serverInfo", mcp.server_info()),
            ])
          let body = mcp.success_response(id, result)
          mcp.json_response(body: body, status: 200)
          |> wisp.set_header("mcp-session-id", session_id)
        }
        Error(_) -> {
          let body =
            mcp.error_response(
              Some(id),
              mcp.InternalError,
              "Failed to create session",
            )
          mcp.json_response(body: body, status: 500)
        }
      }
    }
    Ok(mcp.McpRequest(id: id, method: method, ..)) -> {
      let body =
        mcp.error_response(
          Some(id),
          mcp.MethodNotFound,
          "Expected initialize, got: " <> method,
        )
      mcp.json_response(body: body, status: 400)
    }
    Ok(mcp.McpNotification(..)) -> wisp.response(202)
  }
}

// --- Request Dispatch ---

fn handle_request(
  id id: json.Json,
  method method: String,
  params params: Option(dynamic.Dynamic),
  context context: Context,
  session_id session_id: Option(String),
  user_id user_id: Int,
) -> Response {
  // Touch session
  case session_id {
    Some(sid) ->
      case
        db.exec(
          conn: context.db,
          query: sql.touch_mcp_session(
            last_seen_at: time.now_unix(),
            session_id: sid,
          ),
        )
      {
        Ok(Nil) -> Nil
        Error(_) ->
          logging.log(logging.Warning, "Failed to touch MCP session: " <> sid)
      }
    None -> Nil
  }

  case method {
    "initialize" -> {
      // Already initialized — this shouldn't happen with a session_id
      let body =
        mcp.error_response(Some(id), mcp.InvalidRequest, "Already initialized")
      mcp.json_response(body: body, status: 400)
    }
    "tools/list" -> {
      let result = mcp_tools.tool_schemas()
      let body = mcp.success_response(id, result)
      mcp.json_response(body: body, status: 200)
    }
    "tools/call" ->
      handle_tools_call(
        id: id,
        params: params,
        db: context.db,
        user_id: user_id,
      )
    "ping" -> {
      let body = mcp.success_response(id, json.object([]))
      mcp.json_response(body: body, status: 200)
    }
    _ -> {
      let body =
        mcp.error_response(
          Some(id),
          mcp.MethodNotFound,
          "Method not found: " <> method,
        )
      mcp.json_response(body: body, status: 400)
    }
  }
}

fn handle_notification(method method: String) -> Response {
  case method {
    "notifications/initialized" -> Nil
    _ ->
      logging.log(logging.Debug, "Unknown MCP notification method: " <> method)
  }
  wisp.response(202)
}

// --- Tools Call ---

fn handle_tools_call(
  id id: json.Json,
  params params: Option(dynamic.Dynamic),
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> Response {
  case params {
    None -> {
      let body =
        mcp.error_response(
          Some(id),
          mcp.InvalidParams,
          "Missing params for tools/call",
        )
      mcp.json_response(body: body, status: 400)
    }
    Some(params_value) ->
      parse_and_call_tool(
        id: id,
        params_value: params_value,
        db: db,
        user_id: user_id,
      )
  }
}

fn parse_and_call_tool(
  id id: json.Json,
  params_value params_value: dynamic.Dynamic,
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> Response {
  let decoder = {
    use name <- decode.field("name", decode.string)
    use arguments <- decode.optional_field(
      "arguments",
      None,
      decode.dynamic |> decode.map(Some),
    )
    decode.success(#(name, arguments))
  }
  case decode.run(params_value, decoder) {
    Error(_) -> {
      let body =
        mcp.error_response(
          Some(id),
          mcp.InvalidParams,
          "Invalid params: expected {name, arguments}",
        )
      mcp.json_response(body: body, status: 400)
    }
    Ok(#(name, arguments)) -> {
      let args = case arguments {
        Some(a) -> a
        None -> dynamic.nil()
      }
      let result =
        mcp_tools.call_tool(
          name: name,
          arguments: args,
          db: db,
          user_id: user_id,
        )
      let body = mcp.success_response(id, result)
      mcp.json_response(body: body, status: 200)
    }
  }
}

// --- Session Validation ---

pub fn validate_session(
  db db: sqlight.Connection,
  session_id session_id: String,
) -> Result(Int, Nil) {
  case
    db.query_one(conn: db, query: sql.get_mcp_session(session_id: session_id))
  {
    Ok(Some(session)) -> Ok(session.user_id)
    _ -> Error(Nil)
  }
}

pub fn delete_session(
  db db: sqlight.Connection,
  session_id session_id: String,
) -> Response {
  case
    db.exec(conn: db, query: sql.delete_mcp_session(session_id: session_id))
  {
    Ok(Nil) -> Nil
    Error(err) -> {
      let sqlight.SqlightError(_, message, _) = err
      logging.log(logging.Warning, "Failed to delete MCP session: " <> message)
    }
  }
  wisp.response(204)
}

// --- Helpers ---

fn generate_session_id() -> String {
  auth.random_hex(bytes: 16)
}
