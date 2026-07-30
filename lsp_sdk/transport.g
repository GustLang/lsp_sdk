"""Base-protocol transport: framing JSON-RPC messages over stdio.

Each message on the wire is `Content-Length: <n>\r\n\r\n<body>`, where `<n>`
is the byte length of the UTF-8 JSON `<body>`. Gust strings are byte-indexed
(`"".length` counts bytes), so `body.length` is exactly the `Content-Length`
value and a read of `n` bytes takes exactly the framed body.

Reads go through a `MessageReader`, which pulls stdin in chunks and hands out
one message at a time. Chunking is what keeps a large body cheap: a header is
scanned inside the buffer instead of costing a syscall per byte, and a body is
assembled from whole chunks and joined once rather than grown one piece at a
time. The reader also answers whether another message is pending, which is what
lets a server coalesce a burst of edits instead of analyzing each one.

A read reports a `ReadResult` rather than a bare message, because a bad frame
and a closed stream call for opposite responses: the stream ending is the only
reason to stop, while a frame the reader cannot make sense of is answered with
`parse_error` and the loop continues. Collapsing the two would let one mis-cased
header or one truncated body take the server down without a word.

`encode_message` is a pure function (handy to unit-test); `MessageReader.read`
and `write_message` are the stdio entry points the server loop drives.
"""


use json
use os

# Bytes requested per stdin read. Large enough that a header block and a
# typical body each come back in one syscall, small enough that the buffer
# holding the unconsumed tail stays negligible.


STDIN_CHUNK_BYTES: constant[integer] = 65536

# Byte value of the line feed ending a header field.


LF_BYTE: constant[integer] = 10

# The `Content-Length` field name, lowercased once for the case-insensitive
# comparison a header match needs.


CONTENT_LENGTH_LOWER: constant[string] = "content-length"


enum ReadStatus: integer
    """How a `MessageReader.read` ended.

    Variants:
        ok: A complete, well-formed message was parsed.
        eof: Standard input ended cleanly between messages; the loop stops.
        malformed: The frame or its body could not be parsed. The loop answers
            `parse_error` and keeps reading.
    """

    ok = 0
    eof = 1
    malformed = 2

end


def ReadResult
    """The outcome of one read attempt.

    Fields:
        status: Which of the three outcomes occurred.
        msg: The parsed message object, set only when `status` is `ok`.
        detail: Why the frame was rejected, set only when `status` is
            `malformed`; carried into the `parse_error` response.
    """

    status: ReadStatus = ReadStatus.eof
    msg: Any = none
    detail: string = ""

end


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


def MessageReader
    """Buffered reader framing base-protocol messages from standard input.

    Fields:
        buf: Bytes read from stdin and not yet consumed.
        pos: Index into `buf` of the first unconsumed byte.
        at_eof: Set once a read reported end of input.
    """

    buf: string = ""
    pos: integer = 0
    at_eof: bool = false

end


def MessageReader.read() -> ReadResult
    """Read one framed message from stdin.

    Reports `eof` only when the stream ends between frames — with the header
    block not yet started and nothing buffered. Every other failure (a header
    block cut short, a missing or unparseable `Content-Length`, a body shorter
    than its declared length, a body that is not a JSON object) is `malformed`,
    which the caller answers rather than dies on.

    Header field names are matched case-insensitively, since the base protocol
    inherits HTTP's rules for them and clients do not agree on the casing.
    """
    content_length := -1
    saw_field := false
    while true
        line, complete := _read_header_line()
        if not complete
            if not saw_field and line.trim() == ""
                return ReadResult(status: ReadStatus.eof)
            end
            return _malformed("input ended inside the header block")
        end
        header := line.trim()
        if header == ""
            break
        end
        saw_field = true
        name, value := _split_header_field(header)
        if name.lowercase() == CONTENT_LENGTH_LOWER
            try
                content_length = value as integer
            catch ValueError
                content_length = -1
            end
        end
    end
    if not saw_field
        return _malformed("header block carries no fields")
    end
    if content_length < 0
        return _malformed("missing or unparseable " + CONTENT_LENGTH_HEADER)
    end
    if content_length == 0
        return _malformed(CONTENT_LENGTH_HEADER + " is zero")
    end
    body := _read_exact(content_length)
    short := f"body ended after {body.length} of {content_length} bytes"
    return _malformed(short) if body.length < content_length else _parse_body(body)
end


def MessageReader.pending(timeout_ms: integer) -> bool
    """True when another message's bytes are already buffered, or arrive on
    stdin within `timeout_ms` milliseconds. A zero timeout tests without
    waiting. False once input has ended, so a caller polling for more work is
    not kept alive by a closed stream.

    Arguments:
        timeout_ms: Milliseconds to wait; 0 polls, negative waits indefinitely.
    """
    if pos < buf.length
        return true
    end
    return false if at_eof else os.fd_wait_readable(0, timeout_ms)
end


def private MessageReader._read_header_line() -> tuple[string, bool]
    """The next line-feed-terminated header line, without its terminator, and
    whether the terminator was actually seen. A trailing carriage return is left
    for the caller to trim.

    A false second member means input ended before the line did: the bytes
    returned alongside it are whatever was buffered, which the caller reads to
    tell a clean end of stream from a frame cut in half.
    """
    while true
        i := pos
        while i < buf.length and buf.byte_at(i) != LF_BYTE
            i = i + 1
        end
        if i < buf.length
            line := buf.substring(pos, i)
            pos = i + 1
            _compact()
            return (line, true)
        end
        if not _fill()
            rest := buf.substring(pos, buf.length)
            pos = buf.length
            _compact()
            return (rest, false)
        end
    end
    return ("", false)
end


def private MessageReader._read_exact(n: integer) -> string
    """Exactly `n` bytes: whatever the buffer holds, then whole reads from
    stdin for the remainder. Returns fewer bytes only when input ends first.
    The pieces are joined once, so a large body is copied a single time rather
    than regrown per chunk.
    """
    parts: list[string] = []
    remaining := n
    buffered := buf.length - pos
    if buffered > 0
        take := buffered if buffered < remaining else remaining
        parts.append(buf.substring(pos, pos + take))
        pos = pos + take
        remaining = remaining - take
        _compact()
    end
    while remaining > 0 and not at_eof
        count, chunk := os.read_fd(0, remaining)
        if count <= 0
            at_eof = true
            break
        end
        parts.append(chunk as string)
        remaining = remaining - count
    end
    return "".join(parts)
end


def private MessageReader._fill() -> bool
    """Append one chunk of stdin to the buffer. Returns false at end of input."""
    if at_eof
        return false
    end
    count, chunk := os.read_fd(0, STDIN_CHUNK_BYTES)
    if count <= 0
        at_eof = true
        return false
    end
    buf = buf.substring(pos, buf.length) + (chunk as string)
    pos = 0
    return true
end


def private MessageReader._compact() -> none
    """Release the buffer once every byte in it has been consumed, so a large
    read-ahead is not held for the life of the reader.
    """
    if pos >= buf.length
        buf = ""
        pos = 0
    end
end


def private _parse_body(body: string) -> ReadResult
    """The framed body as a message, or a `malformed` result naming what is
    wrong with it. A body that parses to anything but a JSON object is rejected
    here rather than by every classifier downstream.
    """
    try
        parsed := json.parse(body)
        ok := ReadResult(status: ReadStatus.ok, msg: parsed)
        return ok if parsed is dict else _malformed("body is not a JSON object")
    catch ValueError
        return _malformed("body is not valid JSON")
    end
end


def private _split_header_field(header: string) -> tuple[string, string]
    """A `Name: value` header line as its name and its value, both trimmed. A
    line with no colon yields an empty name, which matches no known field.
    """
    colon := header.index_of(":")
    if colon < 0
        return ("", "")
    end
    name := header.substring(0, colon).trim()
    return (name, header.substring(colon + 1, header.length).trim())
end


def private _malformed(detail: string) -> ReadResult
    """A rejected-frame result carrying `detail` for the `parse_error` response."""
    return ReadResult(status: ReadStatus.malformed, detail: detail)
end
