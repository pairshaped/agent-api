import gleam/result
import gleam/string
import glimit/window.{type WindowLimiter}

// --- Rate Limit Configuration

const magic_link_windows = [
  window.Window(window_seconds: 60, max_count: 1),
  window.Window(window_seconds: 900, max_count: 3),
  window.Window(window_seconds: 3600, max_count: 10),
  window.Window(window_seconds: 86_400, max_count: 20),
]

const verify_windows = [
  window.Window(window_seconds: 60, max_count: 2),
  window.Window(window_seconds: 900, max_count: 5),
  window.Window(window_seconds: 3600, max_count: 15),
  window.Window(window_seconds: 86_400, max_count: 30),
]

// --- Public API

/// Create a new rate limiter backed by an ETS table.
pub fn new() -> WindowLimiter {
  window.new()
}

/// Check all rate limit windows for magic link requests.
/// Returns Ok(Nil) if all pass, Error(retry_after) on first failure.
pub fn check_magic_link_request(
  limiter limiter: WindowLimiter,
  email email: String,
  now now: Int,
) -> Result(Nil, Int) {
  check(
    limiter: limiter,
    prefix: "req:",
    email: email,
    windows: magic_link_windows,
    now: now,
  )
}

/// Check all rate limit windows for verification attempts.
/// Returns Ok(Nil) if all pass, Error(retry_after) on first failure.
pub fn check_verification_attempt(
  limiter limiter: WindowLimiter,
  email email: String,
  now now: Int,
) -> Result(Nil, Int) {
  check(
    limiter: limiter,
    prefix: "verify:",
    email: email,
    windows: verify_windows,
    now: now,
  )
}

fn check(
  limiter limiter: WindowLimiter,
  prefix prefix: String,
  email email: String,
  windows windows: List(window.Window),
  now now: Int,
) -> Result(Nil, Int) {
  let key = prefix <> string.lowercase(email)
  window.check(limiter, key, windows, now)
  |> result.map_error(fn(denied) { denied.retry_after })
}

/// Delete expired rate limit entries.
pub fn cleanup(limiter limiter: WindowLimiter, now now: Int) -> Nil {
  window.cleanup(limiter, now)
}
