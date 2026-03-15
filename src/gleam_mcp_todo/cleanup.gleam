import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

import gleam_mcp_todo/db
import gleam_mcp_todo/rate_limiter
import gleam_mcp_todo/sql
import gleam_mcp_todo/time
import glimit/window.{type WindowLimiter}
import logging
import sqlight

const one_day = 86_400

const check_interval = 3_600_000

pub type Message {
  Tick
}

type State {
  State(
    conn: sqlight.Connection,
    rate_limiter: WindowLimiter,
    self: Subject(Message),
  )
}

pub fn start(
  conn conn: sqlight.Connection,
  rate_limiter rate_limiter: WindowLimiter,
) -> Result(Nil, actor.StartError) {
  actor.new_with_initialiser(5000, fn(subject) {
    // Schedule first tick after 1 minute
    process.send_after(subject, 60_000, Tick)
    Ok(
      actor.initialised(State(
        conn: conn,
        rate_limiter: rate_limiter,
        self: subject,
      )),
    )
  })
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(_) { Nil })
}

fn handle_message(
  state state: State,
  message message: Message,
) -> actor.Next(State, Message) {
  let Tick = message
  run_cleanup(state.conn)
  rate_limiter.cleanup(limiter: state.rate_limiter, now: time.now_unix())
  process.send_after(state.self, check_interval, Tick)
  actor.continue(state)
}

fn run_cleanup(conn: sqlight.Connection) -> Nil {
  let now = time.now_unix()
  let cutoff = now - one_day
  // Demo app: delete ALL users older than 24 hours (even active ones).
  // Delete in order: todos -> user_emails -> users
  db.exec_or_log(
    conn: conn,
    query: sql.delete_todos_for_old_users(created_at: cutoff),
    label: "Cleanup: failed to delete todos",
  )
  db.exec_or_log(
    conn: conn,
    query: sql.delete_user_emails_for_old_users(created_at: cutoff),
    label: "Cleanup: failed to delete user_emails",
  )
  db.exec_or_log(
    conn: conn,
    query: sql.delete_old_users(created_at: cutoff),
    label: "Cleanup: failed to delete users",
  )
  // Clean up OAuth and MCP tables
  db.exec_or_log(
    conn: conn,
    query: sql.delete_expired_codes(expires_at: now),
    label: "Cleanup: failed to delete expired auth codes",
  )
  db.exec_or_log(
    conn: conn,
    query: sql.delete_expired_refresh_tokens(expires_at: now),
    label: "Cleanup: failed to delete expired refresh tokens",
  )
  db.exec_or_log(
    conn: conn,
    query: sql.delete_old_mcp_sessions(last_seen_at: now - one_day),
    label: "Cleanup: failed to delete old MCP sessions",
  )
  logging.log(logging.Info, "Cleanup: completed")
}
