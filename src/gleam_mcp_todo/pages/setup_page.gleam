import gleam/json
import lustre/attribute
import lustre/element
import lustre/element/html

import gleam_mcp_todo/pages/layout

pub fn render(url: String) -> String {
  let claude_desktop_config =
    json.object([
      #(
        "mcpServers",
        json.object([
          #("gleam-mcp-todo", json.object([#("url", json.string(url))])),
        ]),
      ),
    ])
    |> json.to_string()
  let claude_code_cmd = "claude mcp add --transport http gleam-mcp-todo " <> url

  layout.wrap(title: "Todo List MCP Server Setup", content: [
    html.h1([attribute.class("mb-4")], [
      element.text("Todo List MCP Server Setup"),
    ]),
    html.p([attribute.class("lead")], [
      element.text(
        "This is a Todo List MCP server. Connect your AI client using the configuration below.",
      ),
    ]),
    html.h3([attribute.class("mt-4")], [element.text("Claude Desktop")]),
    html.div([attribute.class("code-block mt-2")], [
      element.text(claude_desktop_config),
    ]),
    html.h3([attribute.class("mt-4")], [element.text("Cursor")]),
    html.div([attribute.class("code-block mt-2")], [
      element.text(claude_desktop_config),
    ]),
    html.h3([attribute.class("mt-4")], [element.text("Claude Code")]),
    html.div([attribute.class("code-block mt-2")], [
      element.text(claude_code_cmd),
    ]),
    html.hr([attribute.class("mt-4")]),
    html.p([attribute.class("text-muted mt-3")], [
      element.text(
        "The server uses OAuth 2.1 for authentication. Your MCP client will handle the login flow automatically.",
      ),
    ]),
  ])
}
