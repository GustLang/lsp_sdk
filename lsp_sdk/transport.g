"""Base-protocol transport: framing JSON-RPC messages over stdio.

Each message on the wire is `Content-Length: <n>\r\n\r\n<body>`, where `<n>`
is the byte length of the UTF-8 JSON `<body>`. Gust strings are byte-indexed
(`"".length` counts bytes), so `body.length` is exactly the `Content-Length`
value and `os.stdin_read_n(n)` reads exactly the framed body.

`encode_message` is a pure function (handy to unit-test); `read_message` /
`write_message` are the stdio entry points the server loop drives.
"""


use json
use os


def encode_message(msg: Any) -> string
    """Serialize `msg` to a fully framed base-protocol message: the
    `Content-Length` header, the blank-line separator, then the JSON body.
    """
    body := json.encode(msg)
    header := CONTENT_LENGTH_HEADER + HEADER_FIELD_SEPARATOR + (body.length as string)
    return header + HEADER_SEPARATOR + body
end


def write_message(msg: Any) -> none
    """Frame and write one JSON-RPC message to stdout."""
    os.stdout_write(encode_message(msg))
end


def read_message() -> Any
    """Read one framed JSON-RPC message from stdin, returning the parsed body.

    Returns `none` on EOF or on a malformed frame (missing/invalid
    `Content-Length`, a short body, or unparseable JSON), so the caller can
    treat `none` as "stop the loop".
    """
    content_length := -1
    prefix := CONTENT_LENGTH_HEADER + HEADER_FIELD_SEPARATOR
    while true
        line := os.stdin_readline()
        if line == "" and content_length == -1
            # EOF before any header field was seen.
            return none
        end
        header := line.trim()
        if header == ""
            # Blank line: the header block is done, the body follows.
            break
        end
        if header.starts_with(prefix)
            val := header.substring(prefix.length, header.length).trim()
            try
                content_length = val as integer
            catch ValueError
                content_length = -1
            end
        end
    end
    if content_length <= 0
        return none
    end
    body := os.stdin_read_n(content_length)
    if body == ""
        return none
    end
    try
        return json.parse(body)
    catch ValueError
        return none
    end
end
