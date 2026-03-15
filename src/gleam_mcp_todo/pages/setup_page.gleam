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
  let claude_code_cmd =
    "claude mcp add --transport http gleam-mcp-todo " <> url
  let codex_config =
    "[mcp_servers.gleam-mcp-todo]\nurl = \"" <> url <> "\""
  let gemini_cmd =
    "gemini mcp add --transport http gleam-mcp-todo " <> url

  layout.wrap(title: "Todo List MCP Server Setup", content: [
    html.h1([attribute.class("mb-4")], [
      element.text("Todo List MCP Server Setup"),
    ]),
    html.p([attribute.class("lead")], [
      element.text(
        "This is a Todo List MCP server. Connect your AI client using the configuration below.",
      ),
    ]),
    // --- Anthropic ---
    html.h3([attribute.class("mt-4")], [element.text("Claude Desktop")]),
    html.div([attribute.class("code-block mt-2")], [
      element.text(claude_desktop_config),
    ]),
    html.h3([attribute.class("mt-4")], [element.text("Claude Code")]),
    html.div([attribute.class("code-block mt-2")], [
      element.text(claude_code_cmd),
    ]),
    html.h3([attribute.class("mt-4")], [element.text("Cursor")]),
    html.div([attribute.class("code-block mt-2")], [
      element.text(claude_desktop_config),
    ]),
    // --- OpenAI ---
    html.h3([attribute.class("mt-4")], [element.text("ChatGPT Desktop")]),
    html.p([attribute.class("mb-1")], [
      element.text(
        "Settings \u{2192} Connectors \u{2192} Advanced \u{2192} Developer Mode \u{2192} Add connector. Enter the server URL:",
      ),
    ]),
    html.div([attribute.class("code-block mt-2")], [element.text(url)]),
    html.p([attribute.class("text-muted mt-1")], [
      element.text("Requires ChatGPT Plus or Pro subscription."),
    ]),
    html.h3([attribute.class("mt-4")], [element.text("Codex CLI")]),
    html.p([attribute.class("mb-1")], [
      element.text("Add to ~/.codex/config.toml:"),
    ]),
    html.div([attribute.class("code-block mt-2")], [
      element.text(codex_config),
    ]),
    // --- Google ---
    html.h3([attribute.class("mt-4")], [element.text("Gemini CLI")]),
    html.div([attribute.class("code-block mt-2")], [
      element.text(gemini_cmd),
    ]),
    // --- Footer ---
    html.hr([attribute.class("mt-4")]),
    html.p([attribute.class("text-muted mt-3")], [
      element.text(
        "The server uses OAuth 2.1 for authentication. Your MCP client will handle the login flow automatically.",
      ),
    ]),
  ])
}
