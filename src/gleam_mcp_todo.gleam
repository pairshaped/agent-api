import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/result

import dot_env
import envoy
import gleam_mcp_todo/cleanup
import gleam_mcp_todo/context
import gleam_mcp_todo/db
import gleam_mcp_todo/rate_limiter
import gleam_mcp_todo/router
import mist
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  // Load .env
  dot_env.new()
  |> dot_env.set_debug(False)
  |> dot_env.load()

  // Configure logging
  wisp.configure_logger()

  // Read config
  let session_secret = case envoy.get("SESSION_SECRET") {
    Ok(secret) -> secret
    Error(_) -> {
      io.println(
        "WARNING: SESSION_SECRET not set — using insecure default. Set SESSION_SECRET in production!",
      )
      "dev-secret-change-in-production"
    }
  }

  let db_path =
    envoy.get("DB_PATH")
    |> result.unwrap("db/gleam_mcp_todo.db")
  // lint:allow env default

  let port =
    envoy.get("PORT")
    |> result.try(int.parse)
    |> result.unwrap(8080)
  // lint:allow env default

  let bind_address =
    envoy.get("BIND")
    |> result.unwrap("127.0.0.1")
  // lint:allow env default

  // Open database
  let assert Ok(conn) = db.open(path: db_path)
  // lint:allow crash on startup

  // Create rate limiter
  let limiter = rate_limiter.new()

  // Start cleanup task
  let assert Ok(Nil) = cleanup.start(conn: conn, rate_limiter: limiter)
  // lint:allow crash on startup
  let context =
    context.Context(
      db: conn,
      session_secret: session_secret,
      rate_limiter: limiter,
    )

  // Start server
  let assert Ok(_) =
    // lint:allow crash on startup
    wisp_mist.handler(
      fn(req) { router.handle_request(req: req, context: context) },
      session_secret,
    )
    |> mist.new()
    |> mist.port(port)
    |> mist.bind(bind_address)
    |> mist.start()

  io.println("Server started on port " <> int.to_string(port))
  process.sleep_forever()
}
