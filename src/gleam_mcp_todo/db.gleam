import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import logging
import parrot/dev
import sqlight

/// Open a SQLite connection with WAL mode and busy timeout.
pub fn open(path path: String) -> Result(sqlight.Connection, sqlight.Error) {
  use conn <- result.try(sqlight.open(path))
  use _ <- result.try(sqlight.exec("PRAGMA journal_mode=WAL;", conn))
  use _ <- result.try(sqlight.exec("PRAGMA busy_timeout=5000;", conn))
  use _ <- result.try(sqlight.exec("PRAGMA foreign_keys=ON;", conn))
  Ok(conn)
}

/// Convert a parrot Param to a sqlight Value.
fn param(p: dev.Param) -> sqlight.Value {
  case p {
    dev.ParamBool(x) -> sqlight.bool(x)
    dev.ParamFloat(x) -> sqlight.float(x)
    dev.ParamInt(x) -> sqlight.int(x)
    dev.ParamString(x) -> sqlight.text(x)
    dev.ParamBitArray(x) -> sqlight.blob(x)
    dev.ParamNullable(x) -> sqlight.nullable(param, x)
    dev.ParamList(_) -> panic as "sqlite does not support list parameters"
    // lint:allow unreachable exhaustive match
    dev.ParamDate(_) -> panic as "sqlite does not support date parameters"
    // lint:allow unreachable exhaustive match
    dev.ParamTimestamp(_) ->
      // lint:allow unreachable exhaustive match
      panic as "sqlite does not support timestamp parameters"
    dev.ParamDynamic(_) -> panic as "cannot process dynamic parameter"
    // lint:allow unreachable exhaustive match
  }
}

fn params(ps: List(dev.Param)) -> List(sqlight.Value) {
  list.map(ps, param)
}

/// Execute a parrot :one query. Returns Ok(Some(row)) or Ok(None).
pub fn query_one(
  conn conn: sqlight.Connection,
  query query_tuple: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(Option(a), sqlight.Error) {
  let #(sql, query_params, decoder) = query_tuple
  case
    sqlight.query(sql, on: conn, with: params(query_params), expecting: decoder)
  {
    Ok([row]) -> Ok(Some(row))
    Ok([]) -> Ok(None)
    Ok([row, ..]) -> {
      logging.log(logging.Warning, "query_one returned multiple rows")
      Ok(Some(row))
    }
    Error(e) -> Error(e)
  }
}

/// Execute a parrot :many query. Returns a list of rows.
pub fn query_many(
  conn conn: sqlight.Connection,
  query query_tuple: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(List(a), sqlight.Error) {
  let #(sql, query_params, decoder) = query_tuple
  sqlight.query(sql, on: conn, with: params(query_params), expecting: decoder)
}

/// Execute a parrot :exec query (no return data).
pub fn exec(
  conn conn: sqlight.Connection,
  query query_tuple: #(String, List(dev.Param)),
) -> Result(Nil, sqlight.Error) {
  let #(sql, query_params) = query_tuple
  case
    sqlight.query(
      sql,
      on: conn,
      with: params(query_params),
      expecting: decode.success(Nil),
    )
  {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(e)
  }
}

/// Execute a query, logging on failure and returning Nil either way.
pub fn exec_or_log(
  conn conn: sqlight.Connection,
  query query: #(String, List(dev.Param)),
  label label: String,
) -> Nil {
  case exec(conn: conn, query: query) {
    Ok(Nil) -> Nil
    Error(err) -> {
      let sqlight.SqlightError(_, message, _) = err
      logging.log(logging.Error, label <> ": " <> message)
    }
  }
}
