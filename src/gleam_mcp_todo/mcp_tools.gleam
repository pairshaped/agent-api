import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string

import gleam_mcp_todo/mcp
import gleam_mcp_todo/time
import gleam_mcp_todo/todos
import sqlight

// --- Tool Schemas ---

pub fn tool_schemas() -> json.Json {
  json.object([
    #(
      "tools",
      json.preprocessed_array([
        tool_schema(
          name: "list_todos",
          description: "List all your todos",
          properties: json.object([]),
          required: [],
        ),
        tool_schema(
          name: "get_todo",
          description: "Get a todo by ID",
          properties: json.object([
            #(
              "todo_id",
              json.object([
                #("type", json.string("integer")),
                #("description", json.string("The ID of the todo")),
              ]),
            ),
          ]),
          required: ["todo_id"],
        ),
        tool_schema(
          name: "create_todo",
          description: "Create a new todo",
          properties: json.object([
            #(
              "title",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("What needs to be done")),
              ]),
            ),
          ]),
          required: ["title"],
        ),
        tool_schema(
          name: "update_todo",
          description: "Update a todo's title",
          properties: json.object([
            #(
              "todo_id",
              json.object([
                #("type", json.string("integer")),
                #("description", json.string("The ID of the todo to update")),
              ]),
            ),
            #(
              "title",
              json.object([
                #("type", json.string("string")),
                #("description", json.string("The new title")),
              ]),
            ),
          ]),
          required: ["todo_id", "title"],
        ),
        tool_schema(
          name: "complete_todo",
          description: "Toggle a todo's completed status",
          properties: json.object([
            #(
              "todo_id",
              json.object([
                #("type", json.string("integer")),
                #(
                  "description",
                  json.string("The ID of the todo to complete/uncomplete"),
                ),
              ]),
            ),
          ]),
          required: ["todo_id"],
        ),
        tool_schema(
          name: "delete_todo",
          description: "Delete a todo by ID",
          properties: json.object([
            #(
              "todo_id",
              json.object([
                #("type", json.string("integer")),
                #("description", json.string("The ID of the todo to delete")),
              ]),
            ),
          ]),
          required: ["todo_id"],
        ),
      ]),
    ),
  ])
}

fn tool_schema(
  name name: String,
  description description: String,
  properties properties: json.Json,
  required required: List(String),
) -> json.Json {
  json.object([
    #("name", json.string(name)),
    #("description", json.string(description)),
    #(
      "inputSchema",
      json.object([
        #("type", json.string("object")),
        #("properties", properties),
        #("required", json.array(required, json.string)),
      ]),
    ),
  ])
}

// --- Tool Dispatch ---

pub fn call_tool(
  name name: String,
  arguments arguments: dynamic.Dynamic,
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> json.Json {
  case name {
    "list_todos" -> handle_list_todos(db: db, user_id: user_id)
    "get_todo" ->
      handle_get_todo(arguments: arguments, db: db, user_id: user_id)
    "create_todo" ->
      handle_create_todo(arguments: arguments, db: db, user_id: user_id)
    "update_todo" ->
      handle_update_todo(arguments: arguments, db: db, user_id: user_id)
    "complete_todo" ->
      handle_complete_todo(arguments: arguments, db: db, user_id: user_id)
    "delete_todo" ->
      handle_delete_todo(arguments: arguments, db: db, user_id: user_id)
    _ -> mcp.tool_result(is_error: True, text: "Unknown tool: " <> name)
  }
}

// --- Decoders ---

fn todo_id_decoder() -> decode.Decoder(Int) {
  use todo_id <- decode.field("todo_id", decode.int)
  decode.success(todo_id)
}

// --- Tool Handlers ---

fn handle_list_todos(
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> json.Json {
  case todos.list_todos(db: db, user_id: user_id) {
    Ok(todo_list) -> {
      let text = todos.format_todos_list(todo_list)
      mcp.tool_result(is_error: False, text: text)
    }
    Error(_) -> mcp.tool_result(is_error: True, text: "Failed to list todos.")
  }
}

fn handle_get_todo(
  arguments arguments: dynamic.Dynamic,
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> json.Json {
  use todo_id <- with_args(
    arguments: arguments,
    decoder: todo_id_decoder(),
    error_message: "Missing required parameter: todo_id",
  )
  case todos.get_todo(db: db, todo_id: todo_id, user_id: user_id) {
    Ok(item) -> mcp.tool_result(is_error: False, text: todos.format_todo(item))
    Error(error) ->
      mcp.tool_result(is_error: True, text: todo_error_message(error))
  }
}

fn handle_create_todo(
  arguments arguments: dynamic.Dynamic,
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> json.Json {
  let decoder = {
    use title <- decode.field("title", decode.string)
    decode.success(title)
  }
  use title <- with_args(
    arguments: arguments,
    decoder: decoder,
    error_message: "Missing required parameter: title",
  )
  let now = time.now_unix()
  case todos.create_todo(db: db, user_id: user_id, title: title, now: now) {
    Ok(item) -> {
      let text =
        "Todo created (id: "
        <> int.to_string(item.id)
        <> ").\n\n"
        <> todos.format_todo(item)
      mcp.tool_result(is_error: False, text: text)
    }
    Error(error) ->
      mcp.tool_result(is_error: True, text: todo_error_message(error))
  }
}

fn handle_update_todo(
  arguments arguments: dynamic.Dynamic,
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> json.Json {
  let decoder = {
    use todo_id <- decode.field("todo_id", decode.int)
    use title <- decode.field("title", decode.string)
    decode.success(#(todo_id, title))
  }
  use #(todo_id, title) <- with_args(
    arguments: arguments,
    decoder: decoder,
    error_message: "Missing required parameters: todo_id, title",
  )
  let now = time.now_unix()
  case
    todos.update_todo(
      db: db,
      todo_id: todo_id,
      user_id: user_id,
      title: title,
      now: now,
    )
  {
    Ok(item) -> {
      let text = "Todo updated.\n\n" <> todos.format_todo(item)
      mcp.tool_result(is_error: False, text: text)
    }
    Error(error) ->
      mcp.tool_result(is_error: True, text: todo_error_message(error))
  }
}

fn handle_complete_todo(
  arguments arguments: dynamic.Dynamic,
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> json.Json {
  use todo_id <- with_args(
    arguments: arguments,
    decoder: todo_id_decoder(),
    error_message: "Missing required parameter: todo_id",
  )
  let now = time.now_unix()
  case
    todos.complete_todo(db: db, todo_id: todo_id, user_id: user_id, now: now)
  {
    Ok(item) -> {
      let status = case item.completed {
        False -> "marked incomplete"
        True -> "marked complete"
      }
      let text = "Todo " <> status <> ".\n\n" <> todos.format_todo(item)
      mcp.tool_result(is_error: False, text: text)
    }
    Error(error) ->
      mcp.tool_result(is_error: True, text: todo_error_message(error))
  }
}

fn handle_delete_todo(
  arguments arguments: dynamic.Dynamic,
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> json.Json {
  use todo_id <- with_args(
    arguments: arguments,
    decoder: todo_id_decoder(),
    error_message: "Missing required parameter: todo_id",
  )
  case todos.delete_todo(db: db, todo_id: todo_id, user_id: user_id) {
    Ok(Nil) ->
      mcp.tool_result(
        is_error: False,
        text: "Todo " <> int.to_string(todo_id) <> " deleted.",
      )
    Error(error) ->
      mcp.tool_result(is_error: True, text: todo_error_message(error))
  }
}

// --- Helpers ---

fn with_args(
  arguments arguments: dynamic.Dynamic,
  decoder decoder: decode.Decoder(a),
  error_message error_message: String,
  handler handler: fn(a) -> json.Json,
) -> json.Json {
  case decode.run(arguments, decoder) {
    Error(_) -> mcp.tool_result(is_error: True, text: error_message)
    Ok(args) -> handler(args)
  }
}

fn todo_error_message(error: todos.TodoError) -> String {
  case error {
    todos.NotFound -> "Todo not found"
    todos.DatabaseError -> "Internal server error"
    todos.ValidationError(errors: errors) ->
      case errors {
        [#("_", message)] -> message
        _ -> {
          let messages =
            errors
            |> list.map(fn(pair) {
              let #(field, message) = pair
              field <> ": " <> message
            })
          "Validation failed: " <> string.join(messages, ", ")
        }
      }
  }
}
