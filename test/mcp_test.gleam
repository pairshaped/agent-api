import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string

import gleam_mcp_todo/mcp

// --- JSON-RPC Parsing Tests ---

pub fn parse_request_test() {
  let body =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(1)),
      #("method", json.string("initialize")),
    ])
    |> json.to_string()
    |> to_dynamic()

  let assert Ok(mcp.McpRequest(id: _, method: "initialize", params: None)) =
    mcp.parse_message(body)
}

pub fn parse_request_with_params_test() {
  let body =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(1)),
      #("method", json.string("tools/call")),
      #("params", json.object([#("name", json.string("list_todos"))])),
    ])
    |> json.to_string()
    |> to_dynamic()

  let assert Ok(mcp.McpRequest(id: _, method: "tools/call", params: Some(_))) =
    mcp.parse_message(body)
}

pub fn parse_notification_test() {
  let body =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("method", json.string("notifications/initialized")),
    ])
    |> json.to_string()
    |> to_dynamic()

  let assert Ok(mcp.McpNotification(
    method: "notifications/initialized",
    params: None,
  )) = mcp.parse_message(body)
}

pub fn parse_invalid_jsonrpc_version_test() {
  let body =
    json.object([
      #("jsonrpc", json.string("1.0")),
      #("id", json.int(1)),
      #("method", json.string("test")),
    ])
    |> json.to_string()
    |> to_dynamic()

  let assert Error(mcp.InvalidRequest) = mcp.parse_message(body)
}

pub fn parse_missing_method_test() {
  let body =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(1)),
    ])
    |> json.to_string()
    |> to_dynamic()

  let assert Error(mcp.InvalidRequest) = mcp.parse_message(body)
}

// --- Response Builder Tests ---

pub fn success_response_test() {
  let response =
    mcp.success_response(
      id: json.int(1),
      result_value: json.object([#("key", json.string("value"))]),
    )
  assert string.contains(response, "\"jsonrpc\":\"2.0\"")
  assert string.contains(response, "\"id\":1")
  assert string.contains(response, "\"result\"")
}

pub fn error_response_test() {
  let response =
    mcp.error_response(
      id: Some(json.int(1)),
      error: mcp.MethodNotFound,
      message: "Not found",
    )
  assert string.contains(response, "\"code\":-32601")
  assert string.contains(response, "\"message\":\"Not found\"")
}

pub fn error_response_null_id_test() {
  let response =
    mcp.error_response(id: None, error: mcp.ParseError, message: "Parse error")
  assert string.contains(response, "\"id\":null")
  assert string.contains(response, "\"code\":-32700")
}

// --- Tool Result Builder Tests ---

pub fn tool_result_success_test() {
  let result = mcp.tool_result(is_error: False, text: "Hello")
  let text = json.to_string(result)
  assert string.contains(text, "\"type\":\"text\"")
  assert string.contains(text, "\"text\":\"Hello\"")
  assert !string.contains(text, "isError")
}

pub fn tool_result_error_test() {
  let result = mcp.tool_result(is_error: True, text: "Something went wrong")
  let text = json.to_string(result)
  assert string.contains(text, "\"isError\":true")
}

// --- Error Code Tests ---

pub fn error_codes_test() {
  assert mcp.error_code(mcp.ParseError) == -32_700
  assert mcp.error_code(mcp.InvalidRequest) == -32_600
  assert mcp.error_code(mcp.MethodNotFound) == -32_601
  assert mcp.error_code(mcp.InvalidParams) == -32_602
  assert mcp.error_code(mcp.InternalError) == -32_603
}

// --- Helpers ---

fn to_dynamic(json_string: String) -> dynamic.Dynamic {
  let assert Ok(value) = json.parse(json_string, decode.dynamic)
  value
}
