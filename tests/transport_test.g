"""Framing tests: `encode_message` and the `MessageReader` frame parser.

Each reader under test is seeded with the bytes it would have read from stdin
and marked at end of input, so the parser runs against a fixed buffer and never
touches a file descriptor.
"""


use json
use testing

use (
    CONTENT_LENGTH_HEADER,
    HEADER_SEPARATOR,
    MessageReader,
    ReadStatus,
    encode_message,
    message_method,
) from lsp_sdk


def private framed(body: string) -> string
    """`body` wrapped in a correct `Content-Length` header block."""
    return CONTENT_LENGTH_HEADER + ": " + (body.length as string) + HEADER_SEPARATOR + body
end


def private seeded(bytes_in: string) -> MessageReader
    """A reader holding `bytes_in` with the stream already ended."""
    return MessageReader(buf: bytes_in, at_eof: true)
end


@test
def encode_message_counts_body_bytes(t: testing.T) -> none
    msg: dict[string, Any] = {"jsonrpc": "2.0", "method": "ping"}
    wire := encode_message(msg)
    body := json.encode(msg)
    expected := "Content-Length: " + (body.length as string) + "\r\n\r\n" + body
    testing.assert_str(wire, expected, "framed message")
end


@test
def encode_message_length_is_bytes_not_characters(t: testing.T) -> none
    msg: dict[string, Any] = {"text": "héllo"}
    wire := encode_message(msg)
    body := json.encode(msg)
    header := wire.substring(0, wire.index_of("\r\n\r\n"))
    declared := header.substring("Content-Length: ".length, header.length) as integer
    testing.assert_int(declared, body.length, "declared length is the body's byte count")
end


@test
def read_parses_a_well_formed_frame(t: testing.T) -> none
    r := seeded(framed("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"))
    res := r.read()
    testing.assert_true(res.status == ReadStatus.ok, "status is ok")
    testing.assert_str(message_method(res.msg), "initialize", "method")
end


@test
def read_accepts_a_lowercased_header_name(t: testing.T) -> none
    body := "{\"method\":\"ping\"}"
    r := seeded("content-length: " + (body.length as string) + "\r\n\r\n" + body)
    res := r.read()
    testing.assert_true(res.status == ReadStatus.ok, "case-insensitive header name")
    testing.assert_str(message_method(res.msg), "ping", "method")
end


@test
def read_ignores_unknown_header_fields(t: testing.T) -> none
    body := "{\"method\":\"ping\"}"
    header := "Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n"
    r := seeded(header + "Content-Length: " + (body.length as string) + "\r\n\r\n" + body)
    testing.assert_true(r.read().status == ReadStatus.ok, "extra header field is skipped")
end


@test
def read_returns_eof_on_an_empty_stream(t: testing.T) -> none
    testing.assert_true(seeded("").read().status == ReadStatus.eof, "empty stream is EOF")
end


@test
def read_reports_a_missing_content_length(t: testing.T) -> none
    r := seeded("Content-Type: text/plain\r\n\r\n{\"method\":\"ping\"}")
    res := r.read()
    testing.assert_true(res.status == ReadStatus.malformed, "no Content-Length is malformed")
    testing.assert_contains(res.detail, "Content-Length", "detail names the header")
end


@test
def read_reports_a_zero_content_length(t: testing.T) -> none
    res := seeded("Content-Length: 0\r\n\r\n").read()
    testing.assert_true(res.status == ReadStatus.malformed, "zero length is malformed")
end


@test
def read_reports_an_unparseable_content_length(t: testing.T) -> none
    res := seeded("Content-Length: abc\r\n\r\n{}").read()
    testing.assert_true(res.status == ReadStatus.malformed, "non-numeric length is malformed")
end


@test
def read_reports_a_truncated_header_block(t: testing.T) -> none
    res := seeded("Content-Length: 17").read()
    testing.assert_true(res.status == ReadStatus.malformed, "unterminated header is malformed")
    testing.assert_contains(res.detail, "header", "detail names the header block")
end


@test
def read_reports_a_short_body(t: testing.T) -> none
    res := seeded("Content-Length: 40\r\n\r\n{\"method\":\"ping\"}").read()
    testing.assert_true(res.status == ReadStatus.malformed, "short body is malformed")
    testing.assert_contains(res.detail, "body ended", "detail names the body")
end


@test
def read_reports_unparseable_json(t: testing.T) -> none
    res := seeded(framed("{not json")).read()
    testing.assert_true(res.status == ReadStatus.malformed, "bad JSON is malformed")
end


@test
def read_reports_a_non_object_body(t: testing.T) -> none
    testing.assert_true(
        seeded(framed("null")).read().status == ReadStatus.malformed,
        "a literal null body is malformed",
    )
    testing.assert_true(
        seeded(framed("[1,2,3]")).read().status == ReadStatus.malformed,
        "an array body is malformed",
    )
end


@test
def read_walks_consecutive_frames_then_ends(t: testing.T) -> none
    r := seeded(framed("{\"method\":\"a\"}") + framed("{\"method\":\"b\"}"))
    first := r.read()
    second := r.read()
    testing.assert_str(message_method(first.msg), "a", "first frame")
    testing.assert_str(message_method(second.msg), "b", "second frame")
    testing.assert_true(r.read().status == ReadStatus.eof, "stream ends after both frames")
end


@test
def read_survives_a_bad_frame_and_reads_the_next(t: testing.T) -> none
    r := seeded("Content-Length: 9\r\n\r\n{not json" + framed("{\"method\":\"after\"}"))
    testing.assert_true(r.read().status == ReadStatus.malformed, "first frame is rejected")
    good := r.read()
    testing.assert_true(good.status == ReadStatus.ok, "the next frame still parses")
    testing.assert_str(message_method(good.msg), "after", "method of the recovered frame")
end


@test
def read_handles_a_large_body(t: testing.T) -> none
    filler := "x".repeat(200000)
    r := seeded(framed("{\"method\":\"big\",\"params\":{\"text\":\"" + filler + "\"}}"))
    res := r.read()
    testing.assert_true(res.status == ReadStatus.ok, "200 KB body parses")
    testing.assert_str(message_method(res.msg), "big", "method of the large frame")
end


@test
def pending_is_false_once_the_buffer_is_drained(t: testing.T) -> none
    r := seeded(framed("{\"method\":\"only\"}"))
    testing.assert_true(r.pending(0), "bytes are buffered before the read")
    _ := r.read()
    testing.assert_false(r.pending(0), "nothing is pending after the last frame")
end
