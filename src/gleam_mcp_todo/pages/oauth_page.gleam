import gleam/int
import gleam/list
import gleam/string
import gleam/uri

import gleam_mcp_todo/auth
import gleam_mcp_todo/context.{type Context}
import gleam_mcp_todo/oauth
import gleam_mcp_todo/pages/layout
import gleam_mcp_todo/rate_limiter
import gleam_mcp_todo/time
import lustre/attribute
import lustre/element
import lustre/element/html
import wisp.{type Request, type Response}

type OAuthParams {
  OAuthParams(
    client_id: String,
    redirect_uri: String,
    state: String,
    code_challenge: String,
    resource: String,
  )
}

// --- GET /oauth/authorize ---

pub fn authorize_page(
  request request: Request,
  context context: Context,
) -> Response {
  // Extract query params
  let query_params = wisp.get_query(request)
  let client_id = find_param(params: query_params, name: "client_id")
  let redirect_uri = find_param(params: query_params, name: "redirect_uri")
  let state = find_param(params: query_params, name: "state")
  let code_challenge = find_param(params: query_params, name: "code_challenge")
  let resource = find_param(params: query_params, name: "resource")

  // Validate required params
  case client_id, redirect_uri, code_challenge {
    "", _, _ | _, "", _ | _, _, "" -> {
      let html =
        layout.wrap(title: "Authorization Error", content: [
          html.h1([attribute.class("mb-4")], [element.text("Error")]),
          html.p([], [
            element.text(
              "Missing required parameters: client_id, redirect_uri, code_challenge",
            ),
          ]),
        ])
      wisp.html_response(html, 400)
    }
    _, _, _ -> {
      // Validate client_id and redirect_uri against registered clients
      case
        oauth.validate_client(
          context: context,
          client_id: client_id,
          redirect_uri: redirect_uri,
        )
      {
        Error(_) -> {
          let html =
            layout.wrap(title: "Authorization Error", content: [
              html.h1([attribute.class("mb-4")], [element.text("Error")]),
              html.p([], [
                element.text("Unknown client or invalid redirect URI."),
              ]),
            ])
          wisp.html_response(html, 400)
        }
        Ok(_) -> {
          let params =
            OAuthParams(
              client_id: client_id,
              redirect_uri: redirect_uri,
              state: state,
              code_challenge: code_challenge,
              resource: resource,
            )
          // Show login form
          let html = render_login_form(params: params, email: "", error: "")
          wisp.html_response(html, 200)
        }
      }
    }
  }
}

// --- POST /oauth/authorize ---

pub fn authorize_submit(
  request request: Request,
  context context: Context,
) -> Response {
  use form_data <- wisp.require_form(request)
  let fields = form_data.values

  let client_id = find_param(params: fields, name: "client_id")
  let redirect_uri = find_param(params: fields, name: "redirect_uri")
  let state = find_param(params: fields, name: "state")
  let code_challenge = find_param(params: fields, name: "code_challenge")
  let resource = find_param(params: fields, name: "resource")
  let step = find_param(params: fields, name: "step")
  let email = find_param(params: fields, name: "email")
  let code = find_param(params: fields, name: "code")

  let params =
    OAuthParams(
      client_id: client_id,
      redirect_uri: redirect_uri,
      state: state,
      code_challenge: code_challenge,
      resource: resource,
    )

  // Validate client_id and redirect_uri against registered clients
  case
    oauth.validate_client(
      context: context,
      client_id: client_id,
      redirect_uri: redirect_uri,
    )
  {
    Error(_) -> wisp.response(400)
    Ok(_) ->
      case step {
        "email" ->
          handle_email_step(email: email, params: params, context: context)
        "verify" ->
          handle_verify_step(
            email: email,
            code: code,
            params: params,
            context: context,
          )
        _ -> wisp.response(400)
      }
  }
}

fn handle_email_step(
  email email: String,
  params params: OAuthParams,
  context context: Context,
) -> Response {
  let email = string.trim(email)
  case email {
    "" -> {
      let html =
        render_login_form(params: params, email: "", error: "Email is required")
      wisp.html_response(html, 400)
    }
    _ -> handle_email_login(email: email, params: params, context: context)
  }
}

fn handle_email_login(
  email email: String,
  params params: OAuthParams,
  context context: Context,
) -> Response {
  let now = time.now_unix()
  case
    rate_limiter.check_magic_link_request(
      limiter: context.rate_limiter,
      email: email,
      now: now,
    )
  {
    Error(retry_after) -> {
      let html =
        render_login_form(
          params: params,
          email: email,
          error: "Too many requests. Please try again in "
            <> int.to_string(retry_after)
            <> " seconds.",
        )
      wisp.html_response(html, 429)
    }
    Ok(Nil) ->
      case auth.request_login(conn: context.db, email: email, now: now) {
        Ok(login_request) -> {
          let html =
            render_verify_form(
              params: params,
              email: email,
              verification_code: login_request.token,
              error: "",
            )
          wisp.html_response(html, 200)
        }
        Error(_) -> {
          let html =
            render_login_form(
              params: params,
              email: email,
              error: "Failed to send verification code",
            )
          wisp.html_response(html, 500)
        }
      }
  }
}

fn handle_verify_step(
  email email: String,
  code code: String,
  params params: OAuthParams,
  context context: Context,
) -> Response {
  let now = time.now_unix()
  case
    rate_limiter.check_verification_attempt(
      limiter: context.rate_limiter,
      email: email,
      now: now,
    )
  {
    Error(retry_after) -> {
      let html =
        render_verify_form(
          params: params,
          email: email,
          verification_code: "",
          error: "Too many attempts. Please try again in "
            <> int.to_string(retry_after)
            <> " seconds.",
        )
      wisp.html_response(html, 429)
    }
    Ok(Nil) ->
      handle_verification(
        email: email,
        code: code,
        params: params,
        context: context,
        now: now,
      )
  }
}

fn handle_verification(
  email email: String,
  code code: String,
  params params: OAuthParams,
  context context: Context,
  now now: Int,
) -> Response {
  case
    auth.verify_login(conn: context.db, email: email, token: code, now: now)
  {
    Ok(user) ->
      handle_verified_user(user_id: user.id, params: params, context: context)
    Error(auth.InvalidToken) | Error(auth.SupersededToken) -> {
      let html =
        render_verify_form(
          params: params,
          email: email,
          verification_code: "",
          error: "Invalid verification code. Please try again.",
        )
      wisp.html_response(html, 400)
    }
    Error(auth.ExpiredToken) -> {
      let html =
        render_verify_form(
          params: params,
          email: email,
          verification_code: "",
          error: "Verification code expired. Please request a new one.",
        )
      wisp.html_response(html, 400)
    }
    Error(_) -> {
      let html =
        render_login_form(
          params: params,
          email: email,
          error: "Authentication failed",
        )
      wisp.html_response(html, 500)
    }
  }
}

fn handle_verified_user(
  user_id user_id: Int,
  params params: OAuthParams,
  context context: Context,
) -> Response {
  case
    oauth.create_authorization_code(
      context: context,
      client_id: params.client_id,
      user_id: user_id,
      redirect_uri: params.redirect_uri,
      code_challenge: params.code_challenge,
      resource: params.resource,
      scope: "",
    )
  {
    Ok(auth_code) -> {
      let redirect_url =
        params.redirect_uri
        <> "?code="
        <> uri.percent_encode(auth_code)
        <> "&state="
        <> uri.percent_encode(params.state)
      wisp.redirect(redirect_url)
    }
    Error(_) -> {
      let html =
        layout.wrap(title: "Error", content: [
          html.h1([], [element.text("Error")]),
          html.p([], [
            element.text("Failed to generate authorization code."),
          ]),
        ])
      wisp.html_response(html, 500)
    }
  }
}

// --- HTML Rendering ---

fn render_login_form(
  params params: OAuthParams,
  email email: String,
  error error: String,
) -> String {
  layout.wrap(title: "Log in", content: [
    html.h1([attribute.class("mb-4")], [element.text("Log in")]),
    html.p([attribute.class("text-muted")], [
      element.text("Enter your email to receive a verification code."),
    ]),
    case error {
      "" -> element.none()
      msg ->
        html.div([attribute.class("alert alert-danger")], [
          element.text(msg),
        ])
    },
    html.form(
      [attribute.method("POST"), attribute.action("/oauth/authorize")],
      list.flatten([
        oauth_hidden_fields(params),
        [
          hidden_input(name: "step", value: "email"),
          html.div([attribute.class("mb-3")], [
            html.label([attribute.class("form-label"), attribute.for("email")], [
              element.text("Email"),
            ]),
            html.input([
              attribute.type_("email"),
              attribute.class("form-control"),
              attribute.id("email"),
              attribute.name("email"),
              attribute.value(email),
              attribute.required(True),
              attribute.attribute("autofocus", ""),
            ]),
          ]),
          html.button(
            [attribute.type_("submit"), attribute.class("btn btn-primary")],
            [element.text("Send code")],
          ),
        ],
      ]),
    ),
  ])
}

fn render_verify_form(
  params params: OAuthParams,
  email email: String,
  verification_code verification_code: String,
  error error: String,
) -> String {
  layout.wrap(title: "Verify", content: [
    html.h1([attribute.class("mb-4")], [element.text("Verify")]),
    html.p([], [
      element.text("Enter the verification code for "),
      html.strong([], [element.text(email)]),
    ]),
    case verification_code {
      "" -> element.none()
      code ->
        html.div([attribute.class("token-display mb-3")], [
          html.strong([], [element.text("Your code: ")]),
          element.text(code),
        ])
    },
    case error {
      "" -> element.none()
      msg ->
        html.div([attribute.class("alert alert-danger")], [
          element.text(msg),
        ])
    },
    html.form(
      [attribute.method("POST"), attribute.action("/oauth/authorize")],
      list.flatten([
        oauth_hidden_fields(params),
        [
          hidden_input(name: "step", value: "verify"),
          hidden_input(name: "email", value: email),
          html.div([attribute.class("mb-3")], [
            html.label([attribute.class("form-label"), attribute.for("code")], [
              element.text("Verification code"),
            ]),
            html.input([
              attribute.type_("text"),
              attribute.class("form-control"),
              attribute.id("code"),
              attribute.name("code"),
              attribute.required(True),
              attribute.attribute("autofocus", ""),
              attribute.attribute("autocomplete", "off"),
            ]),
          ]),
          html.button(
            [attribute.type_("submit"), attribute.class("btn btn-primary")],
            [element.text("Verify")],
          ),
        ],
      ]),
    ),
  ])
}

fn oauth_hidden_fields(params: OAuthParams) -> List(element.Element(Nil)) {
  [
    hidden_input(name: "client_id", value: params.client_id),
    hidden_input(name: "redirect_uri", value: params.redirect_uri),
    hidden_input(name: "state", value: params.state),
    hidden_input(name: "code_challenge", value: params.code_challenge),
    hidden_input(name: "resource", value: params.resource),
  ]
}

fn hidden_input(name name: String, value value: String) -> element.Element(Nil) {
  html.input([
    attribute.type_("hidden"),
    attribute.name(name),
    attribute.value(value),
  ])
}

// --- Helpers ---

fn find_param(
  params params: List(#(String, String)),
  name name: String,
) -> String {
  case list.key_find(params, name) {
    Ok(value) -> value
    Error(_) -> ""
  }
}
