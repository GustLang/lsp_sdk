"""Core structural types from the LSP 3.18 specification.

Each type is a plain Gust struct whose field names track the JSON keys, so it
serializes with `json.encode` / `as dict` through the compiler-synthesized
`__dict` and parses back with the `dict as Struct` cast — no per-type
conversion functions. A struct overrides `__dict` only where a JSON key is a
Gust reserved word (`Range.end_pos` → `end`, `Location.rng`/`TextEdit.rng` →
`range`) or where an unset optional field must be omitted from the wire form.
"""

# ── Position / Range ──────────────────────────────────────────────────


def Position
    """A zero-based `(line, character)` position in a text document. The
    character offset is interpreted per the negotiated position encoding
    (UTF-16 code units by default).
    """

    line: integer
    character: integer

end


def Range
    """A half-open range `[start, end)` in a text document.

    Fields:
        start: The inclusive start position.
        end_pos: The exclusive end position. `end` is a reserved word in Gust,
            so this field is named `end_pos` and serialized under the JSON key
            `end`.
    """

    start: Position
    end_pos: Position

end


def Range.__dict() -> dict[string, Any]
    """Serialize with `end_pos` under the reserved JSON key `end`."""
    return {"start": start, "end": end_pos}
end

# ── Location ──────────────────────────────────────────────────────────


def Location
    """A range within a document, identified by URI — the shape returned by
    go-to-definition, references, and workspace symbol requests.

    Fields:
        uri: The document URI.
        rng: The range within the document. `range` collides with the builtin,
            so this field is named `rng` and serialized under the JSON key
            `range`.
    """

    uri: string
    rng: Range

end


def Location.__dict() -> dict[string, Any]
    """Serialize with `rng` under the JSON key `range`."""
    return {"uri": uri, "range": rng}
end


def make_location(
    uri: string,
    start_line: integer,
    start_char: integer,
    end_line: integer,
    end_char: integer,
) -> Location
    """Convenience constructor for a Location from raw line/character offsets."""
    r := Range(
        start: Position(line: start_line, character: start_char),
        end_pos: Position(line: end_line, character: end_char),
    )
    return Location(uri: uri, rng: r)
end

# ── Text document identifiers ─────────────────────────────────────────


def TextDocumentIdentifier
    """Identifies a text document by its URI."""

    uri: string

end


def VersionedTextDocumentIdentifier
    """A `TextDocumentIdentifier` carrying the document version the client
    believes is current — sent with every `didChange`.
    """

    uri: string
    version: integer

end


def TextDocumentItem
    """A text document opened on the client, delivered by `didOpen`."""

    uri: string
    languageId: string
    version: integer
    text: string

end


def TextDocumentPositionParams
    """The common shape of position-based requests (hover, definition,
    completion, signature help): a document identifier plus a cursor Position.
    Nests exactly like the JSON, so `params as TextDocumentPositionParams`
    parses it whole.
    """

    textDocument: TextDocumentIdentifier
    position: Position

end

# ── Edits ─────────────────────────────────────────────────────────────


def TextEdit
    """A single edit: replace the text in `range` with `newText` (an
    insertion is an empty range, a deletion an empty `newText`).

    Fields:
        rng: The range to replace. `range` collides with the builtin, so this
            field is named `rng` and serialized under the JSON key `range`.
        newText: The replacement text.
    """

    rng: Range
    newText: string

end


def TextEdit.__dict() -> dict[string, Any]
    """Serialize with `rng` under the JSON key `range`."""
    return {"range": rng, "newText": newText}
end

# ── Markup / commands ─────────────────────────────────────────────────


def MarkupContent
    """Human-readable content that renders as plain text or Markdown, per
    `kind` (`MARKUP_PLAINTEXT` / `MARKUP_MARKDOWN`).
    """

    kind: string
    value: string

end


def markdown(value: string) -> MarkupContent
    """Build Markdown MarkupContent."""
    return MarkupContent(kind: MARKUP_MARKDOWN, value: value)
end


def plaintext(value: string) -> MarkupContent
    """Build plain-text MarkupContent."""
    return MarkupContent(kind: MARKUP_PLAINTEXT, value: value)
end


def Command
    """A command the client can run — a title plus a registered command id and
    its arguments.
    """

    title: string
    command: string
    arguments: list[Any] = []

end

# ── Diagnostics ───────────────────────────────────────────────────────


def DiagnosticRelatedInformation
    """A related message and source location attached to a diagnostic (e.g.
    "originally declared here").
    """

    location: Location
    message: string

end


def Diagnostic
    """A problem detected in a document, surfaced in the editor.

    `severity` uses the `SEVERITY_*` constants (0 = unset → omitted). `code`
    is a string code (`""` omits it). `tags` holds `DIAGNOSTIC_TAG_*` values.
    """

    rng: Range
    message: string
    severity: integer = 0
    code: string = ""
    source: string = ""
    tags: list[integer] = []
    related: list[DiagnosticRelatedInformation] = []

end


def Diagnostic.__dict() -> dict[string, Any]
    """Serialize, mapping `rng`/`related` to the JSON keys `range`/
    `relatedInformation` and omitting unset optional fields.
    """
    o: dict[string, Any] = {"range": rng, "message": message}
    if severity != 0
        o["severity"] = severity
    end
    put_str(o, "code", code)
    put_str(o, "source", source)
    if tags.length > 0
        o["tags"] = tags
    end
    if related.length > 0
        o["relatedInformation"] = related
    end
    return o
end


def PublishDiagnosticsParams
    """The params of a `textDocument/publishDiagnostics` notification: the set
    of diagnostics currently in effect for `uri` (an empty list clears them).
    """

    uri: string
    diagnostics: list[Diagnostic] = []
    version: integer = 0
    has_version: bool = false

end


def PublishDiagnosticsParams.__dict() -> dict[string, Any]
    """Serialize `uri`/`diagnostics`, adding `version` only when set. The
    internal `has_version` flag is not part of the wire form.
    """
    o: dict[string, Any] = {"uri": uri, "diagnostics": diagnostics}
    if has_version
        o["version"] = version
    end
    return o
end

# ── Completion ────────────────────────────────────────────────────────


def CompletionItem
    """One entry in a completion response. `kind` uses `COMPLETION_KIND_*`
    (0 = unset), `insertTextFormat` uses `INSERT_FORMAT_*`. Unset optional
    fields are omitted.
    """

    label: string
    kind: integer = 0
    detail: string = ""
    documentation: string = ""
    insertText: string = ""
    sortText: string = ""
    filterText: string = ""
    insertTextFormat: integer = 0
    deprecated: bool = false
    preselect: bool = false

end


def CompletionItem.__dict() -> dict[string, Any]
    """Serialize, omitting every unset optional field (an unset `kind`/
    `insertTextFormat` of 0 is not a valid protocol value).
    """
    o: dict[string, Any] = {"label": label}
    if kind != 0
        o["kind"] = kind
    end
    put_str(o, "detail", detail)
    put_str(o, "documentation", documentation)
    put_str(o, "insertText", insertText)
    put_str(o, "sortText", sortText)
    put_str(o, "filterText", filterText)
    if insertTextFormat != 0
        o["insertTextFormat"] = insertTextFormat
    end
    if deprecated
        o["deprecated"] = true
    end
    if preselect
        o["preselect"] = true
    end
    return o
end


def CompletionList
    """A set of completion items with an `isIncomplete` flag that, when true,
    tells the client to re-query as the user keeps typing.
    """

    isIncomplete: bool = false
    items: list[CompletionItem] = []

end

# ── Hover ─────────────────────────────────────────────────────────────


def Hover
    """The result of a hover request: `contents` to render, and an optional
    `range` the hover applies to (`none` to omit).
    """

    contents: MarkupContent
    rng: Range | none = none

end


def Hover.__dict() -> dict[string, Any]
    """Serialize `contents`, adding `range` (from `rng`) only when present."""
    o: dict[string, Any] = {"contents": contents}
    if rng is not none
        o["range"] = rng
    end
    return o
end

# ── Signature help ────────────────────────────────────────────────────


def ParameterInformation
    """One parameter of a signature, with an optional documentation string."""

    label: string
    documentation: string = ""

end


def SignatureInformation
    """One callable signature: its label, optional documentation, and the list
    of its parameters.
    """

    label: string
    documentation: string = ""
    parameters: list[ParameterInformation] = []

end


def SignatureHelp
    """The result of a signature-help request: the candidate signatures and
    which signature / parameter is currently active.
    """

    signatures: list[SignatureInformation] = []
    activeSignature: integer = 0
    activeParameter: integer = 0

end
