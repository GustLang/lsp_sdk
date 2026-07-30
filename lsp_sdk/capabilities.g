"""Lifecycle and capability types for the LSP handshake.

The first request a client sends is `initialize`, carrying its
`ClientCapabilities`; the server answers with an `InitializeResult` describing
the `ServerCapabilities` it will honor. `ServerCapabilities` models the common
providers; a provider is advertised only when enabled (a boolean provider set
to true, or an options struct set to non-`none`), matching the spec's "omit
what you don't support" convention.

`initialize_params_from_json` pulls the fields a server usually needs out of
the `initialize` params, leaving the full raw client capabilities available as
a native `Any` for anything not modeled here.
"""

# ── Provider option structs ───────────────────────────────────────────


def CompletionOptions
    """`completionProvider` options: the characters that trigger completion
    and whether the server resolves items lazily.
    """

    trigger_characters: list[string] = []
    resolve_provider: bool = false

end


def CompletionOptions.__dict() -> dict[string, Any]
    o: dict[string, Any] = {}
    if trigger_characters.length > 0
        o["triggerCharacters"] = trigger_characters
    end

    if resolve_provider
        o["resolveProvider"] = true
    end
    return o
end


def SignatureHelpOptions
    """`signatureHelpProvider` options: the characters that trigger and
    re-trigger signature help.
    """

    trigger_characters: list[string] = []
    retrigger_characters: list[string] = []

end


def SignatureHelpOptions.__dict() -> dict[string, Any]
    o: dict[string, Any] = {}
    if trigger_characters.length > 0
        o["triggerCharacters"] = trigger_characters
    end
    if retrigger_characters.length > 0
        o["retriggerCharacters"] = retrigger_characters
    end
    return o
end

# ── Server capabilities ───────────────────────────────────────────────


def ServerCapabilities
    """The subset of `ServerCapabilities` the SDK models directly.

    `text_document_sync` uses the `SYNC_*` constants, or -1 to omit.
    `position_encoding` uses the `ENCODING_*` constants (`""` omits it).
    Boolean providers advertise a simple capability; `completion` and
    `signature_help` advertise an options object when non-`none`. Anything not
    modeled here can be merged in by the caller after serialization.
    """

    position_encoding: string = ""
    text_document_sync: integer = -1
    hover_provider: bool = false
    definition_provider: bool = false
    declaration_provider: bool = false
    type_definition_provider: bool = false
    implementation_provider: bool = false
    references_provider: bool = false
    document_highlight_provider: bool = false
    document_symbol_provider: bool = false
    workspace_symbol_provider: bool = false
    code_action_provider: bool = false
    document_formatting_provider: bool = false
    document_range_formatting_provider: bool = false
    rename_provider: bool = false
    completion: CompletionOptions | none = none
    signature_help: SignatureHelpOptions | none = none

end


def ServerCapabilities.__dict() -> dict[string, Any]
    o: dict[string, Any] = {}
    put_str(o, "positionEncoding", position_encoding)
    if text_document_sync >= 0
        o["textDocumentSync"] = text_document_sync
    end
    _put_provider(o, "hoverProvider", hover_provider)
    _put_provider(o, "definitionProvider", definition_provider)
    _put_provider(o, "declarationProvider", declaration_provider)
    _put_provider(o, "typeDefinitionProvider", type_definition_provider)
    _put_provider(o, "implementationProvider", implementation_provider)
    _put_provider(o, "referencesProvider", references_provider)
    _put_provider(o, "documentHighlightProvider", document_highlight_provider)
    _put_provider(o, "documentSymbolProvider", document_symbol_provider)
    _put_provider(o, "workspaceSymbolProvider", workspace_symbol_provider)
    _put_provider(o, "codeActionProvider", code_action_provider)
    _put_provider(o, "documentFormattingProvider", document_formatting_provider)
    _put_provider(
        o,
        "documentRangeFormattingProvider",
        document_range_formatting_provider,
    )
    _put_provider(o, "renameProvider", rename_provider)
    if completion is not none
        o["completionProvider"] = completion
    end
    if signature_help is not none
        o["signatureHelpProvider"] = signature_help
    end
    return o
end


def default_server_capabilities() -> ServerCapabilities
    """A minimal capability set advertising full-document text sync and nothing
    else — a reasonable starting point a server can enable providers on.
    """
    return ServerCapabilities(text_document_sync: SYNC_FULL)
end

# ── Initialize handshake ──────────────────────────────────────────────


def ServerInfo
    """The server's self-description, returned in `InitializeResult`."""

    name: string
    version: string = ""

end


def ServerInfo.__dict() -> dict[string, Any]
    o: dict[string, Any] = {"name": name}
    put_str(o, "version", version)
    return o
end


def InitializeResult
    """The `initialize` response: the negotiated capabilities and optional
    server info.
    """

    capabilities: ServerCapabilities
    server_info: ServerInfo | none = none

end


def InitializeResult.__dict() -> dict[string, Any]
    o: dict[string, Any] = {"capabilities": capabilities}
    if server_info is not none
        o["serverInfo"] = server_info
    end
    return o
end


def InitializeParams
    """The fields of `initialize` params a server commonly needs. The full raw
    client capabilities and initialization options are kept as native `Any` for
    anything not surfaced as a typed field.

    Fields:
        process_id: The client's OS process id, or 0 when null.
        root_uri: The workspace root URI, or "" when null.
        client_name: The client's `clientInfo.name`, or "".
        client_version: The client's `clientInfo.version`, or "".
        capabilities: The raw `ClientCapabilities` object.
        initialization_options: The raw `initializationOptions`, or none.
    """

    process_id: integer = 0
    root_uri: string = ""
    client_name: string = ""
    client_version: string = ""
    capabilities: Any
    initialization_options: Any

end


def initialize_params_from_json(v: Any) -> InitializeParams
    """Parse the commonly-used fields out of `initialize` params. Optional
    members (`clientInfo`, `rootUri`, `initializationOptions`) may be absent, so
    each is read leniently rather than via a `dict as Struct` cast.
    """
    obj := v as dict[string, Any]
    process_id := 0
    if "processId" in obj
        pid := obj["processId"]
        if pid is integer
            process_id = pid as integer
        end
    end
    root_uri := ""
    if "rootUri" in obj
        root := obj["rootUri"]
        if root is string
            root_uri = root as string
        end
    end
    client_name := ""
    client_version := ""
    if "clientInfo" in obj
        info := obj["clientInfo"] as dict[string, Any]
        if "name" in info
            name_v := info["name"]
            if name_v is string
                client_name = name_v as string
            end
        end
        if "version" in info
            ver_v := info["version"]
            if ver_v is string
                client_version = ver_v as string
            end
        end
    end
    caps: Any = none
    if "capabilities" in obj
        caps = obj["capabilities"]
    end
    init_opts: Any = none
    if "initializationOptions" in obj
        init_opts = obj["initializationOptions"]
    end
    return InitializeParams(
        process_id: process_id,
        root_uri: root_uri,
        client_name: client_name,
        client_version: client_version,
        capabilities: caps,
        initialization_options: init_opts,
    )
end


def private _put_provider(o: dict[string, Any], key: string, enabled: bool) -> none
    """Advertise a boolean provider `key` only when `enabled`."""
    if enabled
        o[key] = true
    end
end
