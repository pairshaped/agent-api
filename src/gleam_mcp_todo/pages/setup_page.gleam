import lustre/attribute
import lustre/element
import lustre/element/html

import gleam_mcp_todo/pages/layout

pub fn render(url: String) -> String {
  let claude_code_cmd =
    "claude mcp add --transport http gleam-mcp-todo " <> url

  layout.wrap(title: "Todo List MCP Server Setup", content: [
    html.h1([attribute.class("mb-4")], [
      element.text("Todo List MCP Server Setup"),
    ]),
    html.p([attribute.class("lead")], [
      element.text(
        "This is a Todo List MCP server. Connect using one of the options below.",
      ),
    ]),
    html.h3([attribute.class("mt-4")], [element.text("Claude.ai")]),
    html.p([attribute.class("text-muted mb-1")], [
      element.text(
        "Requires Pro, Max, Team, or Enterprise plan. Currently in beta.",
      ),
    ]),
    html.ol([], [
      html.li([], [
        element.text(
          "Go to Settings \u{2192} Connectors \u{2192} Add custom connector",
        ),
      ]),
      html.li([], [
        element.text("Paste the server URL and click Add:"),
      ]),
    ]),
    html.div([attribute.class("code-block mt-2")], [element.text(url)]),
    html.ol([attribute.attribute("start", "3")], [
      html.li([], [
        element.text(
          "In a conversation, click + (lower left) \u{2192} Connectors to enable it",
        ),
      ]),
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
