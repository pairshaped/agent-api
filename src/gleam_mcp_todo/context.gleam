import glimit/window.{type WindowLimiter}
import sqlight

pub type Context {
  Context(
    db: sqlight.Connection,
    session_secret: String,
    rate_limiter: WindowLimiter,
  )
}
