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

The loop is defensive by construction: a frame it cannot parse is answered with
`parse_error`, a handler that raises is answered with `internal_error`, and
neither ends the session. Only the client — through `exit`, or by closing the
stream — decides when the server stops.
"""


def Server
    """An LSP server: a registry of method handlers plus the lifecycle state
    the `serve()` loop maintains.

    Fields:
        server_info: Advertised in the default `initialize` response, or none.
        capabilities: Advertised in the default `initialize` response; a
            default full-sync capability set is used when none.
        req_handlers: Registered request handlers, keyed by method name.
        notif_handlers: Registered notification handlers, keyed by method name.
        debounce_windows: Coalescing window in milliseconds for each
            notification method registered through `set_notification_debounce`.
        resp_ids / resp_handlers: Parallel lists correlating an outstanding
            server-to-client request id with the handler awaiting its response.
        reader: The buffered stdin framer `serve()` reads from.
        pending_msgs: Messages already read but not yet dispatched — held while
            an earlier notification coalesced, or while the loop drained the
            stream looking for cancellations. Dispatched in arrival order.
        cancelled_ids: Ids named by `$/cancelRequest` notifications whose
            request has not started yet.
        initialized: Set once `initialize` has been answered. Before that, every
            other request fails with `server_not_initialized`.
        shutdown_requested: Set once `shutdown` is received; a subsequent
            request other than `exit` fails with `invalid_request`.
        exit_code: The status `serve()` settled on — 0 when the session was shut
            down first, 1 when it ended without one.
    """

    server_info: ServerInfo | none = none
    capabilities: ServerCapabilities | none = none
    req_handlers: dict[string, Function(Any)[Any]] = {}
    notif_handlers: dict[string, Function(Any)[none]] = {}
    debounce_windows: dict[string, integer] = {}
    resp_ids: list[Any] = []
    resp_handlers: list[Function(Any, Any)[none]] = []
    reader: MessageReader = MessageReader()
    pending_msgs: list[Any] = []
    cancelled_ids: list[Any] = []
    initialized: bool = false
    shutdown_requested: bool = false
    exit_code: integer = 0

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
    req_handlers[method] = handler
end


def Server.on_notification(method: string, handler: Function(Any)[none]) -> none
    """Register `handler` for notifications for `method`. The handler is called
    with the params and returns nothing.
    """
    notif_handlers[method] = handler
end


def Server.on_response(id: Any, handler: Function(Any, Any)[none]) -> none
    """Register `handler` to receive the client's response to the
    server-to-client request carrying `id`.

    Without this, a response has nowhere to go and is discarded, so a request
    like `workspace/configuration` can never round-trip. The handler is called
    once with `(result, error)` — exactly one of which is set — and then
    forgotten. Register it before sending the request.

    Arguments:
        id: The id the matching `request` call will carry.
        handler: Called with the response's `result` and `error` members.
    """
    resp_ids.append(id)
    resp_handlers.append(handler)
end


def Server.set_capabilities(caps: ServerCapabilities) -> none
    """Set the capabilities advertised by the default `initialize` response."""
    capabilities = caps
end


def Server.set_notification_debounce(method: string, window_ms: integer) -> none
    """Coalesce bursts of `method` notifications that target the same document:
    after one arrives, `serve()` waits up to `window_ms` for a newer one and
    delivers only the last of the run.

    Register this for a notification whose handler is expensive and whose
    payload supersedes its predecessor — `textDocument/didChange` under full
    document sync is the archetype, where the client sends the whole buffer per
    keystroke and every text but the newest is already obsolete. Messages of
    other kinds that arrive during the window are not dropped; they dispatch in
    order once the coalesced notification is handled.

    Arguments:
        method: The notification method to coalesce.
        window_ms: Milliseconds to wait for a newer notification; 0 disables.
    """
    debounce_windows[method] = window_ms
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
    if "initialize" in req_handlers
        _run_request("initialize", id, req_handlers["initialize"], params)
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

    A request first drains whatever the client has already sent, so a
    `$/cancelRequest` that overtook it is seen before the work starts and the
    request is answered `request_cancelled` instead of computed and thrown away.
    """
    if id is not none and method in req_handlers
        _drain_ready()
        if _take_cancelled(id)
            respond_error(id, ErrorCodes.request_cancelled, "request cancelled")
            return
        end
        _run_request(method, id, req_handlers[method], params)
        return
    end
    if method in notif_handlers
        _run_notification(method, notif_handlers[method], params)
        return
    end
    if id is not none
        respond_error(id, ErrorCodes.method_not_found, "method not found: " + method)
    end
end


def Server.serve() -> none
    """Run the message loop until the client sends `exit` (or stdin reaches
    EOF). Blocks the calling thread; typically the last call in `main`.

    Leaves `exit_code` at the status the session earned: 0 when `shutdown`
    preceded the end, 1 when the client left without one. Nothing else stops the
    loop — an unreadable frame is answered with `parse_error` and a handler that
    raises with `internal_error`, and reading continues either way.
    """
    while true
        res := _next_message()
        if res.status == ReadStatus.eof
            break
        end
        if res.status == ReadStatus.malformed
            respond_error(
                none,
                ErrorCodes.parse_error,
                "malformed message: " + res.detail,
            )
            continue
        end
        if _handle_message(res.msg)
            break
        end
    end
    exit_code = 0 if shutdown_requested else 1
end


def private Server._handle_message(incoming: Any) -> bool
    """Route one well-formed message. Returns true when it ends the session."""
    msg := incoming
    method := message_method(msg)
    id := message_id(msg)
    if method == ""
        _deliver_response(msg)
        return false
    end
    if method == "exit"
        return true
    end
    if method == CANCEL_REQUEST_METHOD
        _record_cancel(message_params(msg))
        return false
    end
    if id is none
        msg = _coalesce_notification(method, msg)
    end
    _route(method, id, message_params(msg))
    return false
end


def private Server._route(method: string, id: Any, params: Any) -> none
    """Apply the lifecycle rules to one message, then hand it to `dispatch`.

    Nothing but `initialize` runs before the handshake, and nothing but `exit`
    runs after `shutdown` — in both cases a request is refused with the code the
    spec names and a notification is dropped silently.
    """
    if method == "initialize"
        _handle_handshake(id, params)
        return
    end
    if not initialized
        _refuse(id, ErrorCodes.server_not_initialized, "server not initialized")
        return
    end
    if method == "shutdown"
        shutdown_requested = true
        respond(id, none)
        return
    end
    if shutdown_requested
        _refuse(id, ErrorCodes.invalid_request, "server is shutting down")
        return
    end
    dispatch(method, id, params)
end


def private Server._handle_handshake(id: Any, params: Any) -> none
    """Answer the `initialize` request, refusing a second one."""
    if id is none
        return
    end
    if initialized
        respond_error(id, ErrorCodes.invalid_request, "server is already initialized")
        return
    end
    handle_initialize(id, params)
    initialized = true
end


def private Server._refuse(id: Any, code: integer, message: string) -> none
    """Refuse a request the lifecycle does not allow right now. A notification
    (no id) is dropped instead, since the spec forbids answering one.
    """
    if id is not none
        respond_error(id, code, message)
    end
end


def private Server._run_request(
    method: string,
    id: Any,
    handler: Function(Any)[Any],
    params: Any,
) -> none
    """Invoke a request handler and answer with its result, or with
    `internal_error` when it raises. A raise that reached the loop would leave
    the client waiting on this id forever.
    """
    result: Any = none
    raised := false
    try
        result = handler(params)
    catch
        raised = true
    end
    if raised
        respond_error(id, ErrorCodes.internal_error, "handler for " + method + " raised")
        return
    end
    respond(id, result)
end


def private Server._run_notification(
    method: string,
    handler: Function(Any)[none],
    params: Any,
) -> none
    """Invoke a notification handler, reporting a raise to the editor's output
    channel. There is no id to answer, so the session simply carries on.
    """
    try
        handler(params)
    catch
        log_message(MESSAGE_TYPE_ERROR, "handler for " + method + " raised")
    end
end


def private Server._deliver_response(msg: Any) -> none
    """Hand a client response to the handler registered for its id, if any, and
    forget the correlation. An uncorrelated response is ignored.
    """
    id := message_id(msg)
    i := _response_index(id)
    if i < 0
        return
    end
    handler := resp_handlers[i]
    resp_ids.delete(i)
    resp_handlers.delete(i)
    try
        handler(_member(msg, "result"), _member(msg, "error"))
    catch
        log_message(MESSAGE_TYPE_ERROR, "response handler raised")
    end
end


def private Server._response_index(id: Any) -> integer
    """Index of the handler awaiting the response to request `id`, or -1."""
    for i in range(resp_ids.length)
        if _same_id(resp_ids[i], id)
            return i
        end
    end
    return -1
end


def private Server._record_cancel(params: Any) -> none
    """Note the request id a `$/cancelRequest` names, so a request still queued
    behind it is answered `request_cancelled` rather than computed.
    """
    id := _member(params, "id")
    if id is not none
        cancelled_ids.append(id)
    end
end


def private Server._take_cancelled(id: Any) -> bool
    """True when `id` was cancelled, consuming the record so a later request
    reusing the id is unaffected.
    """
    for i in range(cancelled_ids.length)
        if _same_id(cancelled_ids[i], id)
            cancelled_ids.delete(i)
            return true
        end
    end
    return false
end


def private Server._drain_ready() -> none
    """Read every message already waiting on stdin into `pending_msgs`, lifting
    out the `$/cancelRequest` notifications among them.

    This is what makes cancellation useful in a single-threaded loop: the
    cancellations a client sent while an earlier request ran are only visible
    once they have been read off the stream.
    """
    while reader.pending(0)
        res := reader.read()
        if res.status == ReadStatus.eof
            return
        end
        if res.status == ReadStatus.malformed
            respond_error(
                none,
                ErrorCodes.parse_error,
                "malformed message: " + res.detail,
            )
            continue
        end
        if message_method(res.msg) == CANCEL_REQUEST_METHOD
            _record_cancel(message_params(res.msg))
            continue
        end
        pending_msgs.append(res.msg)
    end
end


def private Server._next_message() -> ReadResult
    """The next message to dispatch: one held back by an earlier drain or
    debounce window, otherwise a fresh read from stdin.
    """
    if pending_msgs.length > 0
        held := pending_msgs[0]
        pending_msgs.delete(0)
        return ReadResult(status: ReadStatus.ok, msg: held)
    end
    return reader.read()
end


def private Server._coalesce_notification(method: string, msg: Any) -> Any
    """Supersede `msg` with the newest same-document `method` notification that
    arrives within its debounce window, discarding the ones it replaces.

    A message of any other kind seen while waiting ends the window and is queued,
    so dispatch order is preserved: the coalesced notification is handled first,
    then the message that interrupted it.
    """
    window := _debounce_window(method)
    if window <= 0
        return msg
    end
    newest := msg
    uri := _document_uri(newest)
    while reader.pending(window)
        res := reader.read()
        if res.status == ReadStatus.eof
            return newest
        end
        if res.status == ReadStatus.malformed
            respond_error(
                none,
                ErrorCodes.parse_error,
                "malformed message: " + res.detail,
            )
            continue
        end
        if message_method(res.msg) == method and _document_uri(res.msg) == uri
            newest = res.msg
            continue
        end
        pending_msgs.append(res.msg)
        return newest
    end
    return newest
end


def private Server._debounce_window(method: string) -> integer
    """The debounce window registered for notification `method`, or 0 when it
    is not coalesced.
    """
    return debounce_windows[method] if method in debounce_windows else 0
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


def private _document_uri(msg: Any) -> string
    """The `textDocument.uri` a message's params name, or "" when they name no
    document. Coalescing compares it so notifications about different files are
    never collapsed into one.
    """
    doc := _member(message_params(msg), "textDocument")
    uri := _member(doc, "uri")
    return (uri as string) if uri is string else ""
end


def private _member(v: Any, key: string) -> Any
    """The value at `key` in JSON object `v`, or `none` when `v` is not an
    object or has no such key. Read by index rather than through an optional
    `get`, so the result keeps the tag an `is`/`as` narrowing needs.
    """
    if v is not dict
        return none
    end
    d := v as dict[string, Any]
    return d[key] if key in d else none
end


def private _same_id(a: Any, b: Any) -> bool
    """True when two JSON-RPC ids denote the same request. An id is an integer
    or a string, and the two never match each other.
    """
    if a is integer and b is integer
        return (a as integer) == (b as integer)
    end
    return (a as string) == (b as string) if a is string and b is string else false
end
