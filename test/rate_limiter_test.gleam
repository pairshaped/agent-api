import gleam_mcp_todo/rate_limiter

pub fn should_track_magic_link_and_verify_independently_test() {
  let limiter = rate_limiter.new()
  let now = 1_000_000

  // Use up magic link limit (1 per minute)
  let assert Ok(Nil) =
    rate_limiter.check_magic_link_request(
      limiter:,
      email: "test@example.com",
      now:,
    )

  // Magic link blocked
  let assert Error(_) =
    rate_limiter.check_magic_link_request(
      limiter:,
      email: "test@example.com",
      now:,
    )

  // Verification should still work (different action key)
  let assert Ok(Nil) =
    rate_limiter.check_verification_attempt(
      limiter:,
      email: "test@example.com",
      now:,
    )
}

pub fn should_return_retry_after_seconds_test() {
  let limiter = rate_limiter.new()
  let now = 1_000_000

  // Use up magic link limit (1 per minute)
  let assert Ok(Nil) =
    rate_limiter.check_magic_link_request(
      limiter:,
      email: "retry@example.com",
      now:,
    )

  // Should return a retry_after value > 0
  let assert Error(retry_after) =
    rate_limiter.check_magic_link_request(
      limiter:,
      email: "retry@example.com",
      now:,
    )
  let assert True = retry_after > 0
  let assert True = retry_after <= 60
}
