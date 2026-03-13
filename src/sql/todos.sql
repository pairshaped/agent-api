-- name: ListTodosByUser :many
SELECT id, user_id, title, completed, created_at, updated_at
FROM todos WHERE user_id = ? ORDER BY completed ASC, created_at DESC;

-- name: GetTodoById :one
SELECT id, user_id, title, completed, created_at, updated_at
FROM todos WHERE id = ? AND user_id = ?;

-- name: CreateTodo :one
INSERT INTO todos (user_id, title, completed, created_at, updated_at)
VALUES (?, ?, 0, ?, ?)
RETURNING id, user_id, title, completed, created_at, updated_at;

-- name: UpdateTodo :one
UPDATE todos
SET title = ?, updated_at = ?
WHERE id = ? AND user_id = ?
RETURNING id, user_id, title, completed, created_at, updated_at;

-- name: CompleteTodo :one
UPDATE todos
SET completed = CASE WHEN completed = 0 THEN 1 ELSE 0 END, updated_at = ?
WHERE id = ? AND user_id = ?
RETURNING id, user_id, title, completed, created_at, updated_at;

-- name: DeleteTodo :one
DELETE FROM todos WHERE id = (
  SELECT t.id FROM todos t WHERE t.id = ? AND t.user_id = ? LIMIT 1
)
RETURNING id, user_id, title, completed, created_at, updated_at;

-- name: DeleteTodosForOldUsers :exec
DELETE FROM todos WHERE user_id IN (
  SELECT u.id FROM users u WHERE u.created_at < ?
);
