import gleam/bool
import gleam/http.{Delete, Get, Post}
import gleam/list
import gleam/option.{None, Some}
import gleam/string

import gleam_mcp_todo/auth
import gleam_mcp_todo/context.{type Context}
import gleam_mcp_todo/mcp
import gleam_mcp_todo/mcp_handler
import gleam_mcp_todo/oauth
import gleam_mcp_todo/pages/oauth_page
import gleam_mcp_todo/pages/setup_page
import gleam_mcp_todo/time
import wisp.{type Request, type Response}

pub fn handle_request(req req: Request, context context: Context) -> Response {
  use req <- middleware(req: req)

  let segments = wisp.path_segments(req)

  case segments, req.method {
    // Root — MCP or setup page
    [], Post ->
      handle_mcp_post(
        request: req,
        context: context,
        resource: get_resource(req),
      )
    [], Get -> handle_root_get(request: req)
    [], Delete -> handle_mcp_delete(request: req, context: context)

    // Well-known discovery
    [".well-known", "oauth-protected-resource"], Get ->
      oauth.protected_resource_metadata(resource: get_resource(req))
    [".well-known", "oauth-authorization-server"], Get ->
      oauth.authorization_server_metadata(resource: get_resource(req))

    // OAuth endpoints
    ["oauth", "register"], Post ->
      oauth.handle_register(request: req, context: context)
    ["oauth", "authorize"], Get ->
      oauth_page.authorize_page(request: req, context: context)
    ["oauth", "authorize"], Post ->
      oauth_page.authorize_submit(request: req, context: context)
    ["oauth", "token"], Post ->
      oauth.handle_token(request: req, context: context)
    ["oauth", "revoke"], Post ->
      oauth.handle_revoke(request: req, context: context)

    // Robots
    ["robots.txt"], Get ->
      wisp.response(200)
      |> wisp.set_header("content-type", "text/plain; charset=utf-8")
      |> wisp.set_body(wisp.Text("User-agent: *\nAllow: /\n"))

    // Fallback
    _, _ -> wisp.not_found()
  }
}

// --- Root GET ---

fn handle_root_get(request request: Request) -> Response {
  let accept =
    case get_header_option(request: request, name: "accept") {
      Some(value) -> value
      None -> ""
    }
  case string.contains(accept, "text/event-stream") {
    True -> wisp.response(405)
    False -> {
      let html = setup_page.render(get_resource(request))
      wisp.html_response(html, 200)
    }
  }
}

// --- MCP POST ---

fn handle_mcp_post(
  request request: Request,
  context context: Context,
  resource resource: String,
) -> Response {
  let session_id = get_header_option(request: request, name: "mcp-session-id")

  case session_id {
    None -> {
      // No session — must be an initialize request
      // Validate bearer token (OAuth access token)
      case
        get_access_token_user_id(
          request: request,
          context: context,
          resource: resource,
        )
      {
        Ok(user_id) ->
          mcp_handler.handle_initialize_post(
            request: request,
            context: context,
            user_id: user_id,
          )
        Error(err) -> {
          wisp.log_error(
            "Access token validation failed for resource: '"
            <> resource
            <> "' error: "
            <> string.inspect(err),
          )
          unauthorized_response(resource: resource)
        }
      }
    }
    Some(sid) -> {
      // Validate session
      case mcp_handler.validate_session(db: context.db, session_id: sid) {
        Ok(user_id) ->
          mcp_handler.handle_post(
            request: request,
            context: context,
            session_id: Some(sid),
            user_id: user_id,
          )
        Error(_) -> wisp.response(404)
      }
    }
  }
}

// --- MCP DELETE ---

fn handle_mcp_delete(
  request request: Request,
  context context: Context,
) -> Response {
  case get_header_option(request: request, name: "mcp-session-id") {
    Some(session_id) ->
      mcp_handler.delete_session(db: context.db, session_id: session_id)
    None -> wisp.response(400)
  }
}

// --- Auth ---

fn get_access_token_user_id(
  request request: Request,
  context context: Context,
  resource resource: String,
) -> Result(Int, auth.AuthError) {
  let authorization = get_header_option(request: request, name: "authorization")
  case authorization {
    None -> Error(auth.InvalidToken)
    Some(value) -> {
      use <- bool.guard(
        when: !string.starts_with(value, "Bearer "),
        return: Error(auth.InvalidToken),
      )
      let token = string.drop_start(value, 7)
      let now = time.now_unix()
      auth.validate_access_token(
        session_secret: context.session_secret,
        token: token,
        resource: resource,
        now: now,
      )
    }
  }
}

fn unauthorized_response(resource resource: String) -> Response {
  let body =
    mcp.error_response(
      id: None,
      error: mcp.InvalidRequest,
      message: "Authorization required",
    )
  mcp.json_response(body: body, status: 401)
  |> wisp.set_header(
    "www-authenticate",
    "Bearer resource_metadata=\""
      <> resource
      <> "/.well-known/oauth-protected-resource\"",
  )
}

// --- Middleware ---

fn middleware(
  req req: Request,
  handle_request handle_request: fn(Request) -> Response,
) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)

  handle_request(req)
}

// --- Helpers ---

fn get_resource(request: Request) -> String {
  // Use Host header (includes port), falling back to request fields
  case get_header_option(request: request, name: "host") {
    Some(host) -> {
      // Only trust recognized schemes from X-Forwarded-Proto
      let scheme = case
        get_header_option(request: request, name: "x-forwarded-proto")
      {
        Some("https") -> "https"
        Some(_) -> "http"
        None ->
          case request.scheme {
            http.Http -> "http"
            http.Https -> "https"
          }
      }
      // Strip any path from host header to prevent injection
      let sanitized_host = case string.split(host, "/") {
        [h, ..] -> h
        _ -> host
      }
      scheme <> "://" <> sanitized_host
    }
    None -> {
      wisp.log_warning("No Host header; falling back to http://localhost:8080")
      "http://localhost:8080"
    }
  }
}

fn get_header_option(
  request request: Request,
  name name: String,
) -> option.Option(String) {
  list.key_find(request.headers, name) |> option.from_result
}
