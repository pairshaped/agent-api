import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import wisp

// JSON-RPC 2.0 Types

pub type McpMessage {
  McpRequest(id: json.Json, method: String, params: Option(dynamic.Dynamic))
  McpNotification(method: String, params: Option(dynamic.Dynamic))
}

pub type McpError {
  ParseError
  InvalidRequest
  MethodNotFound
  InvalidParams
  InternalError
}

// --- Parsing ---

pub fn parse_message(body: dynamic.Dynamic) -> Result(McpMessage, McpError) {
  let decoder = {
    use jsonrpc <- decode.field("jsonrpc", decode.string)
    use method <- decode.field("method", decode.string)
    use id <- decode.optional_field("id", None, {
      use d <- decode.then(decode.dynamic)
      decode.success(Some(d))
    })
    use params <- decode.optional_field("params", None, {
      use d <- decode.then(decode.dynamic)
      decode.success(Some(d))
    })
    decode.success(#(jsonrpc, method, id, params))
  }

  case decode.run(body, decoder) {
    Error(_) -> Error(InvalidRequest)
    Ok(#(jsonrpc, method, id, params)) -> {
      case jsonrpc {
        "2.0" ->
          case id {
            Some(raw_id) -> {
              let json_id = dynamic_to_json(raw_id)
              Ok(McpRequest(id: json_id, method: method, params: params))
            }
            None -> Ok(McpNotification(method: method, params: params))
          }
        _ -> Error(InvalidRequest)
      }
    }
  }
}

fn dynamic_to_json(value: dynamic.Dynamic) -> json.Json {
  case decode.run(value, decode.int) {
    Ok(i) -> json.int(i)
    Error(_) ->
      case decode.run(value, decode.string) {
        Ok(s) -> json.string(s)
        Error(_) -> json.null()
      }
  }
}

// --- Response Builders ---

pub fn success_response(
  id id: json.Json,
  result_value result_value: json.Json,
) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", id),
    #("result", result_value),
  ])
  |> json.to_string()
}

pub fn error_response(
  id id: Option(json.Json),
  error error: McpError,
  message message: String,
) -> String {
  let id_value = case id {
    Some(id) -> id
    None -> json.null()
  }
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", id_value),
    #(
      "error",
      json.object([
        #("code", json.int(error_code(error))),
        #("message", json.string(message)),
      ]),
    ),
  ])
  |> json.to_string()
}

pub fn error_code(error: McpError) -> Int {
  case error {
    ParseError -> -32_700
    InvalidRequest -> -32_600
    MethodNotFound -> -32_601
    InvalidParams -> -32_602
    InternalError -> -32_603
  }
}

// Tool Result Builders

pub fn tool_result(is_error is_error: Bool, text text: String) -> json.Json {
  let content =
    json.preprocessed_array([
      json.object([
        #("type", json.string("text")),
        #("text", json.string(text)),
      ]),
    ])
  case is_error {
    False -> json.object([#("content", content)])
    True -> json.object([#("content", content), #("isError", json.bool(True))])
  }
}

// --- Server Info ---

pub fn server_capabilities() -> json.Json {
  json.object([#("tools", json.object([]))])
}

pub fn server_info() -> json.Json {
  json.object([
    #("name", json.string("gleam-mcp-todo")),
    #("version", json.string("0.2.0")),
  ])
}

pub const protocol_version = "2025-06-18"

// --- HTTP Response Helpers ---

pub fn json_response(body body: String, status status: Int) -> wisp.Response {
  wisp.response(status)
  |> wisp.set_header("content-type", "application/json")
  |> wisp.set_body(wisp.Text(body))
}

pub fn json_error(status status: Int, message message: String) -> wisp.Response {
  let body =
    json.object([#("error", json.string(message))])
    |> json.to_string()
  json_response(body: body, status: status)
}
