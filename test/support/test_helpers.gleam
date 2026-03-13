import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list

import gleam_mcp_todo/context.{type Context, Context}
import gleam_mcp_todo/rate_limiter
import gleam_mcp_todo/router
import support/test_db
import wisp.{type Request, type Response}
import wisp/simulate

const test_secret = "test-secret-key"

/// Resource URL that matches wisp/simulate defaults (host: localhost, scheme: http)
pub const test_resource = "http://localhost"

pub fn setup() -> Context {
  let conn = test_db.setup()
  Context(
    db: conn,
    session_secret: test_secret,
    rate_limiter: rate_limiter.new(),
  )
}

pub fn handle(req req: Request, context context: Context) -> Response {
  // Override wisp/simulate defaults (host: wisp.example.com, scheme: Https)
  // to use a predictable resource URL: http://localhost
  let req = request.set_scheme(req, http.Http)
  let req = request.set_host(req, "localhost")
  let headers = list.key_set(req.headers, "host", "localhost")
  let req = request.Request(..req, headers: headers)
  router.handle_request(req: req, context: context)
}

pub fn secret() -> String {
  test_secret
}

pub fn read_json_field(
  response response: Response,
  field_name field_name: String,
) -> Result(String, Nil) {
  let body = simulate.read_body(response)
  let decoder = {
    use value <- decode.field(field_name, decode.string)
    decode.success(value)
  }
  case json.parse(body, decoder) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}
