"""A Gust implementation of the Language Server Protocol.

`lsp` is a reusable SDK for writing language servers that speak LSP 3.18 over
stdio. Import it with `use lsp`. The package is organized as:

  * `constants.g`    — base-protocol framing + all protocol enumeration values
  * `message.g`      — JSON-RPC 2.0 envelope: requests, notifications,
                       responses, `ErrorCodes`, and message classifiers
  * `transport.g`    — `Content-Length` framing read/write over stdio
  * `types.g`        — structural types (Position, Range, Location, Diagnostic,
                       CompletionItem, Hover, ...) that serialize via `__dict`
                       and deserialize via a `dict as Struct` cast
  * `capabilities.g` — the `initialize` handshake and `ServerCapabilities`
  * `server.g`       — the `Server` dispatch loop and handler registration
  * `json_build.g`   — the shared `put_str` "omit-when-empty" object helper

Handlers receive and return native JSON values (`Any`): a parsed object is a
`dict[string, Any]`, an array a `list[Any]`, with primitives and `none` as
themselves. A typed struct becomes its wire object with `struct as dict[string,
Any]`, and an incoming object becomes a typed struct with `value as Struct`.

A minimal server:

    use lsp

    def main() -> none
        srv := lsp.new_server("my-language-server", "0.1.0")
        caps := lsp.ServerCapabilities(text_document_sync: lsp.SYNC_FULL, hover_provider: true)
        srv.set_capabilities(caps)
        srv.on_request("textDocument/hover", def(params: Any) -> Any
            hover := lsp.Hover(contents: lsp.markdown("Hello from the server"))
            return hover as dict[string, Any]
        end)
        srv.serve()
    end
"""
