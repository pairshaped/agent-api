import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import logging

import gleam_mcp_todo/db
import gleam_mcp_todo/sql
import sqlight

// --- Types ---

pub type Todo {
  Todo(
    id: Int,
    title: String,
    completed: Bool,
    created_at: Int,
    updated_at: Int,
  )
}

pub type TodoError {
  ValidationError(errors: List(#(String, String)))
  NotFound
  DatabaseError
}

// --- Validation ---

const max_title_length = 500

pub fn validate_title(
  title title: String,
) -> Result(String, List(#(String, String))) {
  let title = string.trim(title)
  case title {
    "" -> Error([#("title", "Required")])
    _ ->
      case string.length(title) > max_title_length {
        True -> Error([#("title", "Must be 500 characters or less")])
        False -> Ok(title)
      }
  }
}

fn log_db_error(label label: String) -> TodoError {
  logging.log(logging.Error, "Database error in " <> label)
  DatabaseError
}

fn todo_from_row(
  id id: Int,
  title title: String,
  completed completed: Int,
  created_at created_at: Int,
  updated_at updated_at: Int,
) -> Todo {
  Todo(
    id: id,
    title: title,
    completed: completed != 0,
    created_at: created_at,
    updated_at: updated_at,
  )
}

// --- CRUD ---

pub fn list_todos(
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> Result(List(Todo), TodoError) {
  case
    db.query_many(conn: db, query: sql.list_todos_by_user(user_id: user_id))
  {
    Ok(rows) ->
      Ok(
        list.map(rows, fn(row) {
          todo_from_row(
            id: row.id,
            title: row.title,
            completed: row.completed,
            created_at: row.created_at,
            updated_at: row.updated_at,
          )
        }),
      )
    Error(_) -> Error(log_db_error(label: "list_todos"))
  }
}

pub fn get_todo(
  db db: sqlight.Connection,
  todo_id todo_id: Int,
  user_id user_id: Int,
) -> Result(Todo, TodoError) {
  case
    db.query_one(
      conn: db,
      query: sql.get_todo_by_id(id: todo_id, user_id: user_id),
    )
  {
    Ok(Some(row)) ->
      Ok(todo_from_row(
        id: row.id,
        title: row.title,
        completed: row.completed,
        created_at: row.created_at,
        updated_at: row.updated_at,
      ))
    Ok(None) -> Error(NotFound)
    Error(_) -> Error(log_db_error(label: "get_todo"))
  }
}

pub fn create_todo(
  db db: sqlight.Connection,
  user_id user_id: Int,
  title title: String,
  now now: Int,
) -> Result(Todo, TodoError) {
  case validate_title(title: title) {
    Error(errors) -> Error(ValidationError(errors: errors))
    Ok(title) -> {
      case
        db.query_one(
          conn: db,
          query: sql.create_todo(
            user_id: user_id,
            title: title,
            created_at: now,
            updated_at: now,
          ),
        )
      {
        Ok(Some(row)) ->
          Ok(todo_from_row(
            id: row.id,
            title: row.title,
            completed: row.completed,
            created_at: row.created_at,
            updated_at: row.updated_at,
          ))
        _ -> Error(log_db_error(label: "create_todo"))
      }
    }
  }
}

pub fn update_todo(
  db db: sqlight.Connection,
  todo_id todo_id: Int,
  user_id user_id: Int,
  title title: String,
  now now: Int,
) -> Result(Todo, TodoError) {
  case validate_title(title: title) {
    Error(errors) -> Error(ValidationError(errors: errors))
    Ok(title) -> {
      case
        db.query_one(
          conn: db,
          query: sql.update_todo(
            title: title,
            updated_at: now,
            id: todo_id,
            user_id: user_id,
          ),
        )
      {
        Ok(Some(row)) ->
          Ok(todo_from_row(
            id: row.id,
            title: row.title,
            completed: row.completed,
            created_at: row.created_at,
            updated_at: row.updated_at,
          ))
        Ok(_) -> Error(NotFound)
        Error(_) -> Error(log_db_error(label: "update_todo"))
      }
    }
  }
}

pub fn complete_todo(
  db db: sqlight.Connection,
  todo_id todo_id: Int,
  user_id user_id: Int,
  now now: Int,
) -> Result(Todo, TodoError) {
  case
    db.query_one(
      conn: db,
      query: sql.complete_todo(updated_at: now, id: todo_id, user_id: user_id),
    )
  {
    Ok(Some(row)) ->
      Ok(todo_from_row(
        id: row.id,
        title: row.title,
        completed: row.completed,
        created_at: row.created_at,
        updated_at: row.updated_at,
      ))
    Ok(None) -> Error(NotFound)
    Error(_) -> Error(log_db_error(label: "complete_todo"))
  }
}

pub fn delete_todo(
  db db: sqlight.Connection,
  todo_id todo_id: Int,
  user_id user_id: Int,
) -> Result(Nil, TodoError) {
  case
    db.query_one(
      conn: db,
      query: sql.delete_todo(id: todo_id, user_id: user_id),
    )
  {
    Ok(Some(_)) -> Ok(Nil)
    Ok(None) -> Error(NotFound)
    Error(_) -> Error(log_db_error(label: "delete_todo"))
  }
}

// --- Formatting ---

pub fn format_todos_list(todos: List(Todo)) -> String {
  let header = case todos {
    [] -> "You have no todos."
    [_] -> "You have 1 todo."
    _ -> "You have " <> int.to_string(list.length(todos)) <> " todos."
  }
  case todos {
    [] -> header
    _ -> {
      let items =
        todos
        |> list.index_map(fn(item, index) {
          let status = case item.completed {
            False -> "[ ]"
            True -> "[x]"
          }
          int.to_string(index + 1)
          <> ". "
          <> status
          <> " \""
          <> item.title
          <> "\" (id: "
          <> int.to_string(item.id)
          <> ")"
        })
        |> string.join("\n")
      header <> "\n\n" <> items
    }
  }
}

pub fn format_todo(item: Todo) -> String {
  let status = case item.completed {
    False -> "incomplete"
    True -> "complete"
  }
  "Todo "
  <> int.to_string(item.id)
  <> ": "
  <> item.title
  <> " ("
  <> status
  <> ")"
}
