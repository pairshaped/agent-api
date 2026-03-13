import gleam/dynamic
import gleam/list
import gleam/string
import logging
import simplifile
import sqlight

// persistent_term FFI — global BEAM cache, perfect for test fixtures
@external(erlang, "persistent_term", "put")
fn pt_put(key: String, value: Result(a, Nil)) -> dynamic.Dynamic

@external(erlang, "persistent_term", "get")
fn pt_get(key: String, default: Result(a, Nil)) -> Result(a, Nil)

// SQLite backup API — page-level clone of an in-memory database
@external(erlang, "test_db_ffi", "clone_db")
fn clone_db(template: sqlight.Connection) -> Result(sqlight.Connection, Nil)

/// Template database with schema pre-loaded. Created once, cloned per test.
fn template_db() -> sqlight.Connection {
  case pt_get("test_template_db", Error(Nil)) {
    Ok(conn) -> conn
    Error(Nil) -> {
      let assert Ok(conn) = sqlight.open(":memory:")
      let assert Ok(_) = sqlight.exec("PRAGMA foreign_keys=ON;", conn)

      // Load all migration files in order
      let assert Ok(files) = simplifile.read_directory("db/migrations")
      let migration_files =
        files
        |> list.sort(string.compare)

      list.each(migration_files, fn(file) {
        let assert Ok(sql) = simplifile.read("db/migrations/" <> file)
        let assert Ok(_) = sqlight.exec(sql, conn)
      })

      let _ = pt_put("test_template_db", Ok(conn))
      conn
    }
  }
}

/// Suppress all application logs during tests (once per run).
fn configure_test_logger() -> Nil {
  case pt_get("test_logger_configured", Error(Nil)) {
    Ok(_) -> Nil
    Error(Nil) -> {
      logging.set_level(logging.Emergency)
      let _ = pt_put("test_logger_configured", Ok(Nil))
      Nil
    }
  }
}

/// Opens an in-memory database with the full schema.
/// Uses SQLite's backup API to clone a cached template at the page level,
/// avoiding re-parsing migrations per test.
pub fn setup() -> sqlight.Connection {
  configure_test_logger()
  let assert Ok(conn) = clone_db(template_db())
  let assert Ok(_) = sqlight.exec("PRAGMA foreign_keys=ON;", conn)
  conn
}
