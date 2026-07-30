"""The `Server` dispatch loop — the front door of the SDK.

A caller builds a `Server`, registers handlers by method name, and calls
`serve()`. `serve()` reads framed messages from stdin, routes each to its
handler, and writes responses back — handling the `initialize` / `shutdown` /
`exit` lifecycle itself so handlers only deal with the methods they care about.

Handlers are ordinary function values:
  * A **request** handler is `Function(Any)[Any]` — it receives the request
    `params` and returns the `result` value.
  * A **notification** handler is `Function(Any)[none]` — it receives the
    `params` and returns nothing.

To share mutable state (a document store, config, ...) across handlers, capture
it in the handler closures; captured heap values are shared by reference.
"""


def Server
    """An LSP server: a registry of method handlers plus the lifecycle state
    the `serve()` loop maintains.

    Fields:
        server_info: Advertised in the default `initialize` response, or none.
        capabilities: Advertised in the default `initialize` response; a
            default full-sync capability set is used when none.
        req_methods / req_handlers: Parallel lists of registered request
            handlers, keyed by method name.
        notif_methods / notif_handlers: Parallel lists of registered
            notification handlers, keyed by method name.
        shutdown_requested: Set once `shutdown` is received; a subsequent
            request other than `exit` should fail with `invalid_request`.
    """

    server_info: ServerInfo | none = none
    capabilities: ServerCapabilities | none = none
    req_methods: list[string] = []
    req_handlers: list[Function(Any)[Any]] = []
    notif_methods: list[string] = []
    notif_handlers: list[Function(Any)[none]] = []
    shutdown_requested: bool = false

end


def new_server(name: string, version: string) -> Server
    """Build a server that advertises itself as `name`/`version`."""
    return Server(server_info: ServerInfo(name: name, version: version))
end

# ── Registration ──────────────────────────────────────────────────────


def Server.on_request(method: string, handler: Function(Any)[Any]) -> none
    """Register `handler` to answer requests for `method`. The handler is
    called with the request params and its return value becomes the response
    result. Registering `"initialize"` overrides the default handshake.
    """
    req_methods.append(method)
    req_handlers.append(handler)
end


def Server.on_notification(method: string, handler: Function(Any)[none]) -> none
    """Register `handler` for notifications for `method`. The handler is called
    with the params and returns nothing.
    """
    notif_methods.append(method)
    notif_handlers.append(handler)
end


def Server.set_capabilities(caps: ServerCapabilities) -> none
    """Set the capabilities advertised by the default `initialize` response."""
    capabilities = caps
end

# ── Outgoing messages ─────────────────────────────────────────────────


def Server.respond(id: Any, result: Any) -> none
    """Send a successful response carrying `result` for request `id`."""
    write_message(make_success_response(id, result))
end


def Server.respond_error(id: Any, code: integer, message: string) -> none
    """Send an error response with `code`/`message` for request `id`."""
    write_message(make_error_response(id, code, message, none))
end


def Server.notify(method: string, params: Any) -> none
    """Send a notification to the client."""
    write_message(make_notification(method, params))
end


def Server.request(id: Any, method: string, params: Any) -> none
    """Send a server-to-client request. Correlating the client's response with
    `id` is left to a handler the caller registers; this only sends.
    """
    write_message(make_request(id, method, params))
end


def Server.publish_diagnostics(params: PublishDiagnosticsParams) -> none
    """Send a `textDocument/publishDiagnostics` notification."""
    notify("textDocument/publishDiagnostics", params as dict[string, Any])
end


def Server.log_message(message_type: integer, message: string) -> none
    """Send a `window/logMessage` notification (goes to the editor's output
    channel). `message_type` uses the `MESSAGE_TYPE_*` constants.
    """
    _window_notify("window/logMessage", message_type, message)
end


def Server.show_message(message_type: integer, message: string) -> none
    """Send a `window/showMessage` notification (a UI popup/toast).
    `message_type` uses the `MESSAGE_TYPE_*` constants.
    """
    _window_notify("window/showMessage", message_type, message)
end

# ── Dispatch ──────────────────────────────────────────────────────────


def Server.handle_initialize(id: Any, params: Any) -> none
    """Answer `initialize`: use a registered `"initialize"` handler if present,
    otherwise reply with the configured (or default) capabilities.
    """
    ridx := _method_index(req_methods, "initialize")
    if ridx >= 0
        respond(id, req_handlers[ridx](params))
        return
    end
    cap_opt := capabilities
    caps := default_server_capabilities()
    if cap_opt is not none
        caps = cap_opt
    end
    result := InitializeResult(capabilities: caps, server_info: server_info)
    respond(id, result as dict[string, Any])
end


def Server.dispatch(method: string, id: Any, params: Any) -> none
    """Route one non-lifecycle message to its registered handler. Requests with
    no matching handler get a `method_not_found` error; unknown notifications
    are ignored, per the spec.
    """
    ridx := _method_index(req_methods, method)
    if ridx >= 0 and id is not none
        respond(id, req_handlers[ridx](params))
        return
    end
    nidx := _method_index(notif_methods, method)
    if nidx >= 0
        notif_handlers[nidx](params)
        return
    end
    if id is not none
        respond_error(id, ErrorCodes.method_not_found, "method not found: " + method)
    end
end


def Server.serve() -> none
    """Run the message loop until the client sends `exit` (or stdin reaches
    EOF). Blocks the calling thread; typically the last call in `main`.
    """
    while true
        msg := read_message()
        if msg is none
            break
        end
        method := message_method(msg)
        id := message_id(msg)
        params := message_params(msg)
        if method == ""
            # A response to a server-to-client request; no built-in routing.
            continue
        end
        match method
            case "initialize"
                handle_initialize(id, params)
            case "shutdown"
                shutdown_requested = true
                respond(id, none)
            case "exit"
                break
            else
                if shutdown_requested and id is not none
                    respond_error(
                        id,
                        ErrorCodes.invalid_request,
                        "server is shutting down",
                    )
                else
                    dispatch(method, id, params)
                end
        end
    end
end


def private Server._window_notify(
    method: string,
    message_type: integer,
    message: string,
) -> none
    """Send a `window/*` notification carrying a `{type, message}` params object."""
    o: dict[string, Any] = {"type": message_type, "message": message}
    notify(method, o)
end


def private _method_index(methods: list[string], target: string) -> integer
    """Index of `target` in `methods`, or -1."""
    for i in range(methods.length)
        if methods[i] == target
            return i
        end
    end
    return - 1
end
