import gleam/list
import gleam/string

import gleam_mcp_todo/auth
import gleam_mcp_todo/todos
import support/test_db

const now = 1_000_000

// --- Validation Tests ---

pub fn validate_title_accepts_valid_input_test() {
  let assert Ok("My Title") = todos.validate_title(title: "My Title")
}

pub fn validate_title_trims_whitespace_test() {
  let assert Ok("Trimmed") = todos.validate_title(title: "  Trimmed  ")
}

pub fn validate_title_rejects_empty_test() {
  let assert Error([#("title", "Required")]) = todos.validate_title(title: "")
}

pub fn validate_title_rejects_whitespace_only_test() {
  let assert Error([#("title", "Required")]) =
    todos.validate_title(title: "   ")
}

pub fn validate_title_rejects_over_500_chars_test() {
  let long_title = string.repeat("a", 501)
  let assert Error([#("title", "Must be 500 characters or less")]) =
    todos.validate_title(title: long_title)
}

pub fn validate_title_accepts_exactly_500_chars_test() {
  let title = string.repeat("a", 500)
  let assert Ok(_) = todos.validate_title(title: title)
}

// --- CRUD Tests ---

fn create_test_user(db) -> Int {
  let assert Ok(user) =
    auth.auto_login(conn: db, email: "test@example.com", now: now)
  user.id
}

pub fn list_todos_empty_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)
  let assert Ok(todo_list) = todos.list_todos(db: db, user_id: user_id)
  assert todo_list == []
}

pub fn create_and_list_todos_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)

  let assert Ok(item) =
    todos.create_todo(db: db, user_id: user_id, title: "Buy milk", now: now)
  assert item.title == "Buy milk"
  assert item.completed == False

  let assert Ok(todo_list) = todos.list_todos(db: db, user_id: user_id)
  assert list.length(todo_list) == 1
}

pub fn get_todo_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)

  let assert Ok(created) =
    todos.create_todo(db: db, user_id: user_id, title: "Find Me", now: now)
  let assert Ok(found) =
    todos.get_todo(db: db, todo_id: created.id, user_id: user_id)
  assert found.title == "Find Me"
  assert found.completed == False
}

pub fn get_todo_not_found_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)
  let assert Error(todos.NotFound) =
    todos.get_todo(db: db, todo_id: 999, user_id: user_id)
}

pub fn update_todo_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)

  let assert Ok(created) =
    todos.create_todo(db: db, user_id: user_id, title: "Original", now: now)
  let assert Ok(updated) =
    todos.update_todo(
      db: db,
      todo_id: created.id,
      user_id: user_id,
      title: "Updated",
      now: now,
    )
  assert updated.title == "Updated"
}

pub fn update_todo_not_found_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)
  let assert Error(todos.NotFound) =
    todos.update_todo(
      db: db,
      todo_id: 999,
      user_id: user_id,
      title: "Nope",
      now: now,
    )
}

pub fn complete_todo_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)

  let assert Ok(created) =
    todos.create_todo(db: db, user_id: user_id, title: "Do this", now: now)
  assert created.completed == False

  let assert Ok(completed) =
    todos.complete_todo(db: db, todo_id: created.id, user_id: user_id, now: now)
  assert completed.completed == True

  let assert Ok(uncompleted) =
    todos.complete_todo(db: db, todo_id: created.id, user_id: user_id, now: now)
  assert uncompleted.completed == False
}

pub fn complete_todo_not_found_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)
  let assert Error(todos.NotFound) =
    todos.complete_todo(db: db, todo_id: 999, user_id: user_id, now: now)
}

pub fn delete_todo_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)

  let assert Ok(created) =
    todos.create_todo(db: db, user_id: user_id, title: "Delete Me", now: now)
  let assert Ok(Nil) =
    todos.delete_todo(db: db, todo_id: created.id, user_id: user_id)
  let assert Error(todos.NotFound) =
    todos.get_todo(db: db, todo_id: created.id, user_id: user_id)
}

pub fn create_todo_validation_error_test() {
  let db = test_db.setup()
  let user_id = create_test_user(db)
  let assert Error(todos.ValidationError(errors: [#("title", "Required")])) =
    todos.create_todo(db: db, user_id: user_id, title: "", now: now)
}

// --- Formatting Tests ---

pub fn format_todos_list_empty_test() {
  assert todos.format_todos_list([]) == "You have no todos."
}
