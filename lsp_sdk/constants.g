"""Protocol constants for the Language Server Protocol.

Two groups live here:

  1. **Base-protocol framing** — the HTTP-style header constants that wrap each
     JSON-RPC message on the wire. `Content-Length` (the byte count of the JSON
     body) is mandatory; `Content-Type` is optional and defaults to UTF-8
     JSON-RPC. See the "Base Protocol" section of the LSP 3.18 spec.

  2. **Protocol enumerations** — the spec's integer/string enumerations
     (severities, kinds, tags, sync modes, ...). These are modeled as prefixed
     `constant` values rather than `enum` types: several LSP members
     collide with reserved words (`error`, `enum`, `interface`, `type`,
     `none`) and so cannot be written as enum members at all. Flat prefixed
     constants are the faithful, uniform representation of the on-the-wire
     values.
     The one clean-named enumeration, JSON-RPC's `ErrorCodes`, *is* an
     `enum` — it lives in `message.g`.

All files under `lsp_sdk/lsp_sdk/` share a single namespace, so these constants are
visible to every other module in the package without an explicit `use`.
"""

# ══ Base-protocol framing ═════════════════════════════════════════════


JSONRPC_VERSION: constant[string] = "2.0"


CONTENT_LENGTH_HEADER: constant[string] = "Content-Length"


CONTENT_TYPE_HEADER: constant[string] = "Content-Type"

# Separator between a header field name and its value (`Name: value`).


HEADER_FIELD_SEPARATOR: constant[string] = ": "

# Line terminator between individual header fields.


CRLF: constant[string] = "\r\n"

# The blank line (`\r\n\r\n`) that ends the header block and precedes the body.


HEADER_SEPARATOR: constant[string] = "\r\n\r\n"

# Default `Content-Type` when a message omits the header.


DEFAULT_CONTENT_TYPE: constant[string] = "application/vscode-jsonrpc; charset=utf-8"

# ══ Protocol enumerations ═════════════════════════════════════════════
# (JSON-RPC's `ErrorCodes` enum lives in `message.g`.)

# ── MessageType (window/showMessage, window/logMessage) ───────────────


MESSAGE_TYPE_ERROR: constant[integer] = 1


MESSAGE_TYPE_WARNING: constant[integer] = 2


MESSAGE_TYPE_INFO: constant[integer] = 3


MESSAGE_TYPE_LOG: constant[integer] = 4


MESSAGE_TYPE_DEBUG: constant[integer] = 5

# ── DiagnosticSeverity ────────────────────────────────────────────────


SEVERITY_ERROR: constant[integer] = 1


SEVERITY_WARNING: constant[integer] = 2


SEVERITY_INFORMATION: constant[integer] = 3


SEVERITY_HINT: constant[integer] = 4

# ── DiagnosticTag ─────────────────────────────────────────────────────


DIAGNOSTIC_TAG_UNNECESSARY: constant[integer] = 1


DIAGNOSTIC_TAG_DEPRECATED: constant[integer] = 2

# ── TextDocumentSyncKind ──────────────────────────────────────────────


SYNC_NONE: constant[integer] = 0


SYNC_FULL: constant[integer] = 1


SYNC_INCREMENTAL: constant[integer] = 2

# ── TextDocumentSaveReason ────────────────────────────────────────────


SAVE_REASON_MANUAL: constant[integer] = 1


SAVE_REASON_AFTER_DELAY: constant[integer] = 2


SAVE_REASON_FOCUS_OUT: constant[integer] = 3

# ── CompletionItemKind ────────────────────────────────────────────────


COMPLETION_KIND_TEXT: constant[integer] = 1


COMPLETION_KIND_METHOD: constant[integer] = 2


COMPLETION_KIND_FUNCTION: constant[integer] = 3


COMPLETION_KIND_CONSTRUCTOR: constant[integer] = 4


COMPLETION_KIND_FIELD: constant[integer] = 5


COMPLETION_KIND_VARIABLE: constant[integer] = 6


COMPLETION_KIND_CLASS: constant[integer] = 7


COMPLETION_KIND_INTERFACE: constant[integer] = 8


COMPLETION_KIND_MODULE: constant[integer] = 9


COMPLETION_KIND_PROPERTY: constant[integer] = 10


COMPLETION_KIND_UNIT: constant[integer] = 11


COMPLETION_KIND_VALUE: constant[integer] = 12


COMPLETION_KIND_ENUM: constant[integer] = 13


COMPLETION_KIND_KEYWORD: constant[integer] = 14


COMPLETION_KIND_SNIPPET: constant[integer] = 15


COMPLETION_KIND_COLOR: constant[integer] = 16


COMPLETION_KIND_FILE: constant[integer] = 17


COMPLETION_KIND_REFERENCE: constant[integer] = 18


COMPLETION_KIND_FOLDER: constant[integer] = 19


COMPLETION_KIND_ENUM_MEMBER: constant[integer] = 20


COMPLETION_KIND_CONSTANT: constant[integer] = 21


COMPLETION_KIND_STRUCT: constant[integer] = 22


COMPLETION_KIND_EVENT: constant[integer] = 23


COMPLETION_KIND_OPERATOR: constant[integer] = 24


COMPLETION_KIND_TYPE_PARAMETER: constant[integer] = 25

# ── CompletionItemTag ─────────────────────────────────────────────────


COMPLETION_TAG_DEPRECATED: constant[integer] = 1

# ── InsertTextFormat ──────────────────────────────────────────────────


INSERT_FORMAT_PLAIN_TEXT: constant[integer] = 1


INSERT_FORMAT_SNIPPET: constant[integer] = 2

# ── InsertTextMode ────────────────────────────────────────────────────


INSERT_MODE_AS_IS: constant[integer] = 1


INSERT_MODE_ADJUST_INDENTATION: constant[integer] = 2

# ── CompletionTriggerKind ─────────────────────────────────────────────


COMPLETION_TRIGGER_INVOKED: constant[integer] = 1


COMPLETION_TRIGGER_CHARACTER: constant[integer] = 2


COMPLETION_TRIGGER_INCOMPLETE: constant[integer] = 3

# ── SymbolKind ────────────────────────────────────────────────────────


SYMBOL_KIND_FILE: constant[integer] = 1


SYMBOL_KIND_MODULE: constant[integer] = 2


SYMBOL_KIND_NAMESPACE: constant[integer] = 3


SYMBOL_KIND_PACKAGE: constant[integer] = 4


SYMBOL_KIND_CLASS: constant[integer] = 5


SYMBOL_KIND_METHOD: constant[integer] = 6


SYMBOL_KIND_PROPERTY: constant[integer] = 7


SYMBOL_KIND_FIELD: constant[integer] = 8


SYMBOL_KIND_CONSTRUCTOR: constant[integer] = 9


SYMBOL_KIND_ENUM: constant[integer] = 10


SYMBOL_KIND_INTERFACE: constant[integer] = 11


SYMBOL_KIND_FUNCTION: constant[integer] = 12


SYMBOL_KIND_VARIABLE: constant[integer] = 13


SYMBOL_KIND_CONSTANT: constant[integer] = 14


SYMBOL_KIND_STRING: constant[integer] = 15


SYMBOL_KIND_NUMBER: constant[integer] = 16


SYMBOL_KIND_BOOLEAN: constant[integer] = 17


SYMBOL_KIND_ARRAY: constant[integer] = 18


SYMBOL_KIND_OBJECT: constant[integer] = 19


SYMBOL_KIND_KEY: constant[integer] = 20


SYMBOL_KIND_NULL: constant[integer] = 21


SYMBOL_KIND_ENUM_MEMBER: constant[integer] = 22


SYMBOL_KIND_STRUCT: constant[integer] = 23


SYMBOL_KIND_EVENT: constant[integer] = 24


SYMBOL_KIND_OPERATOR: constant[integer] = 25


SYMBOL_KIND_TYPE_PARAMETER: constant[integer] = 26

# ── SymbolTag ─────────────────────────────────────────────────────────


SYMBOL_TAG_DEPRECATED: constant[integer] = 1

# ── DocumentHighlightKind ─────────────────────────────────────────────


HIGHLIGHT_TEXT: constant[integer] = 1


HIGHLIGHT_READ: constant[integer] = 2


HIGHLIGHT_WRITE: constant[integer] = 3

# ── MarkupKind (string enum) ──────────────────────────────────────────


MARKUP_PLAINTEXT: constant[string] = "plaintext"


MARKUP_MARKDOWN: constant[string] = "markdown"

# ── PositionEncodingKind (string enum) ────────────────────────────────


ENCODING_UTF8: constant[string] = "utf-8"


ENCODING_UTF16: constant[string] = "utf-16"


ENCODING_UTF32: constant[string] = "utf-32"

# ── CodeActionKind (string enum) ──────────────────────────────────────


CODE_ACTION_QUICKFIX: constant[string] = "quickfix"


CODE_ACTION_REFACTOR: constant[string] = "refactor"


CODE_ACTION_REFACTOR_EXTRACT: constant[string] = "refactor.extract"


CODE_ACTION_REFACTOR_INLINE: constant[string] = "refactor.inline"


CODE_ACTION_REFACTOR_REWRITE: constant[string] = "refactor.rewrite"


CODE_ACTION_SOURCE: constant[string] = "source"


CODE_ACTION_SOURCE_ORGANIZE_IMPORTS: constant[string] = "source.organizeImports"


CODE_ACTION_SOURCE_FIX_ALL: constant[string] = "source.fixAll"
