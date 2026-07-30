"""JSON-RPC 2.0 message layer for the Language Server Protocol.

LSP messages are JSON-RPC 2.0 objects in one of three shapes: a *request*
(has both `id` and `method`, expects a response), a *notification* (has
`method` but no `id`, expects no response), and a *response* (has `id`, and
exactly one of `result` or `error`).

The dynamic members — `id`, `params`, `result`, `data` — are typed `Any`: `id`
is an integer or string, `params`/`result` are arbitrary structured values, and
each is optional in some shapes. A parsed JSON value is already a native `Any`,
so these round-trip through the `json` package unchanged.

The typed structs below model the three shapes; each `__dict` builds its wire
object (omitting the members the spec omits). The `make_*` builders are the
ergonomic way to construct outgoing messages, and the `is_*` / `message_*`
helpers classify and destructure an incoming one.
"""


enum ErrorCodes: integer
    """JSON-RPC 2.0 and LSP base-protocol error codes. Integer-backed, so a
    member passes directly where an `integer` code is expected (e.g.
    `make_error_response(id, ErrorCodes.method_not_found, ...)`) with no cast.
    """

    # Defined by JSON-RPC 2.0.
    parse_error = -32700
    invalid_request = -32600
    method_not_found = -32601
    invalid_params = -32602
    internal_error = -32603

    # Reserved JSON-RPC server-error range.
    server_error_start = -32099
    server_error_end = -32000

    # Defined by the LSP base protocol.
    server_not_initialized = -32002
    unknown_error_code = -32001
    request_failed = -32803
    server_cancelled = -32802
    content_modified = -32801
    request_cancelled = -32800

end

# ── Typed message models ──────────────────────────────────────────────


def RequestMessage
    """A request between client and server. Every processed request must be
    answered with a `ResponseMessage` carrying the same `id`.

    Fields:
        jsonrpc: Always "2.0".
        id: The request id — an integer or string.
        method: The method to be invoked.
        params: The method's params (a JSON object/array), or `none`.
    """

    jsonrpc: string = "2.0"
    id: Any
    method: string
    params: Any

end


def RequestMessage.__dict() -> dict[string, Any]
    """Serialize to a JSON-RPC request object. `params` is omitted when `none`."""
    o: dict[string, Any] = {"jsonrpc": jsonrpc, "id": id, "method": method}
    if params is not none
        o["params"] = params
    end
    return o
end


def NotificationMessage
    """A notification — a fire-and-forget event that must not be answered.

    Fields:
        jsonrpc: Always "2.0".
        method: The method to be invoked.
        params: The notification's params (a JSON object/array), or `none`.
    """

    jsonrpc: string = "2.0"
    method: string
    params: Any

end


def NotificationMessage.__dict() -> dict[string, Any]
    """Serialize to a JSON-RPC notification object (no `id`)."""
    o: dict[string, Any] = {"jsonrpc": jsonrpc, "method": method}
    if params is not none
        o["params"] = params
    end
    return o
end


def ResponseError
    """The error member of a failed response.

    Fields:
        code: A number from `ErrorCodes` (or a custom code) identifying the error.
        message: A short human-readable description.
        data: Optional structured detail, or `none` to omit.
    """

    code: integer
    message: string
    data: Any

end


def ResponseError.__dict() -> dict[string, Any]
    """Serialize to a JSON-RPC error object. `data` is omitted when `none`."""
    o: dict[string, Any] = {"code": code, "message": message}
    if data is not none
        o["data"] = data
    end
    return o
end


def ResponseMessage
    """A response to a request. Carries exactly one of `result` or
    `resp_error`; `result` may be `none` (JSON null) on a successful request
    that produces no value.

    Fields:
        jsonrpc: Always "2.0".
        id: The id of the request being answered (or `none` for a parse error
            where the id could not be determined).
        result: The success result. Ignored when `resp_error` is set.
        resp_error: The error, or none on success. Serialized under the JSON
            key "error" (`error` is a reserved word in Gust).
    """

    jsonrpc: string = "2.0"
    id: Any
    result: Any
    resp_error: ResponseError | none = none

end


def ResponseMessage.__dict() -> dict[string, Any]
    """Serialize to a JSON-RPC response object. Emits `error` when
    `resp_error` is set, otherwise `result` (never both, per the spec).
    """
    o: dict[string, Any] = {"jsonrpc": jsonrpc, "id": id}
    if resp_error is not none
        o["error"] = resp_error
    else
        o["result"] = result
    end
    return o
end

# ── Outgoing-message builders ─────────────────────────────────────────


def make_request(id: Any, method: string, params: Any) -> dict[string, Any]
    """Build a JSON-RPC request object for `method` with `params`."""
    return RequestMessage(id: id, method: method, params: params) as dict[string, Any]
end


def make_notification(method: string, params: Any) -> dict[string, Any]
    """Build a JSON-RPC notification object for `method` with `params`."""
    return NotificationMessage(method: method, params: params) as dict[string, Any]
end


def make_success_response(id: Any, result: Any) -> dict[string, Any]
    """Build a successful JSON-RPC response object carrying `result`."""
    return ResponseMessage(id: id, result: result) as dict[string, Any]
end


def make_error_response(
    id: Any,
    code: integer,
    message: string,
    data: Any,
) -> dict[string, Any]
    """Build a failed JSON-RPC response object with `code`/`message`/`data`.
    Pass `none` for `data` to omit it.
    """
    err := ResponseError(code: code, message: message, data: data)
    return ResponseMessage(id: id, result: none, resp_error: err) as dict[string, Any]
end

# ── Incoming-message classification ───────────────────────────────────


def message_method(msg: Any) -> string
    """The `method` of `msg`, or "" if absent (i.e. `msg` is a response)."""
    d := msg as dict[string, Any]
    if "method" in d
        m := d["method"]
        if m is string
            return m as string
        end
    end
    return ""
end


def message_id(msg: Any) -> Any
    """The `id` of `msg` (`none` if absent)."""
    d := msg as dict[string, Any]
    if "id" in d  #gust-ignore W0509
        return d["id"]
    end
    return none
end


def has_id(msg: Any) -> bool
    """True when `msg` carries an `id` member (a request or a response)."""
    return "id" in (msg as dict[string, Any])
end


def message_params(msg: Any) -> Any
    """The `params` of `msg` (`none` if absent)."""
    d := msg as dict[string, Any]
    if "params" in d  #gust-ignore W0509
        return d["params"]
    end
    return none
end


def is_request(msg: Any) -> bool
    """True when `msg` is a request: it has both a `method` and an `id`."""
    return message_method(msg) != "" and has_id(msg)
end


def is_notification(msg: Any) -> bool
    """True when `msg` is a notification: a `method` but no `id`."""
    return message_method(msg) != "" and not has_id(msg)
end


def is_response(msg: Any) -> bool
    """True when `msg` is a response: an `id` but no `method`."""
    return message_method(msg) == "" and has_id(msg)
end
