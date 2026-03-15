import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn wrap(title title: String, content content: List(Element(Nil))) -> String {
  html.html([attribute.attribute("lang", "en")], [
    html.head([], [
      html.meta([attribute.attribute("charset", "utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.attribute("content", "width=device-width, initial-scale=1"),
      ]),
      html.title([], title),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href(
          "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css",
        ),
      ]),
      html.style(
        [],
        "
        body { background: #f8f9fa; }
        .code-block {
          background: #1e1e1e;
          color: #d4d4d4;
          font-family: monospace;
          font-size: 0.85rem;
          padding: 1rem;
          border-radius: 0.375rem;
          white-space: pre-wrap;
          word-wrap: break-word;
        }
        .token-display {
          background: #fff3cd;
          border: 1px solid #ffc107;
          padding: 0.75rem 1rem;
          border-radius: 0.375rem;
          font-family: monospace;
          word-break: break-all;
        }
      ",
      ),
    ]),
    html.body([], [
      html.div([attribute.class("container py-4")], content),
      html.footer([attribute.class("container py-3 text-center text-muted")], [
        html.a(
          [
            attribute.href(
              "https://github.com/pairshaped/gleam-mcp-todo",
            ),
            attribute.target("_blank"),
          ],
          [element.text("GitHub")],
        ),
      ]),
    ]),
  ])
  |> element.to_document_string
}
