"""Position-encoding conversion between the protocol and byte-indexed text.

A `Position.character` is an offset into a line measured in the negotiated
position encoding — UTF-16 code units unless the client and server agree
otherwise, and UTF-16 is what the spec mandates when neither side says
anything. Gust strings are byte-indexed, so a server that hands the protocol a
byte column reports the wrong place on every line holding a character outside
ASCII: hovers miss, definitions jump to a shifted column, and diagnostics
underline the wrong span.

`negotiate_position_encoding` picks the encoding to advertise from what the
client offers, and the column converters translate at the boundary — positions
in, ranges out — so the server's internals stay byte-indexed. Both converters
return their argument unchanged for an all-ASCII line, which is the common
case.
"""

# UTF-8 lead-byte boundaries. A byte below CONT_MIN is a one-byte character; a
# lead below THREE_MIN introduces two bytes, below FOUR_MIN three, and from
# FOUR_MIN up four — the last being the only form that costs two UTF-16 code
# units (a surrogate pair).


ASCII_MAX: constant[integer] = 0x80


CONT_MIN: constant[integer] = 0xC0


THREE_MIN: constant[integer] = 0xE0


FOUR_MIN: constant[integer] = 0xF0


def negotiate_position_encoding(client_capabilities: Any) -> string
    """The position encoding to advertise, given the client's raw
    `ClientCapabilities`.

    `general.positionEncodings` lists what the client supports, most preferred
    first. UTF-8 is chosen whenever it appears — it costs a byte-indexed server
    no conversion at all — and UTF-16 otherwise, which is what the spec
    prescribes for a client that states nothing.

    Arguments:
        client_capabilities: The `capabilities` object from `initialize`, or
            `none` when the client sent none.
    """
    if client_capabilities is none
        return ENCODING_UTF16
    end
    caps := client_capabilities as dict[string, Any]
    if "general" not in caps
        return ENCODING_UTF16
    end
    general := caps["general"] as dict[string, Any]
    if "positionEncodings" not in general
        return ENCODING_UTF16
    end
    offered := general["positionEncodings"] as list[Any]
    for entry in offered
        if entry is string and (entry as string) == ENCODING_UTF8
            return ENCODING_UTF8
        end
    end
    return ENCODING_UTF16
end


def is_ascii_only(line: string) -> bool
    """True when every byte of `line` is ASCII, so byte offsets and UTF-16 code
    unit offsets into it are the same number.

    Arguments:
        line: The line to test.
    """
    i := 0
    while i < line.length
        if line.byte_at(i) >= ASCII_MAX
            return false
        end
        i = i + 1
    end
    return true
end


def byte_to_utf16_column(line: string, byte_column: integer) -> integer
    """`byte_column` — a byte offset into `line` — as a count of UTF-16 code
    units, which is what a `Position.character` carries under the default
    encoding.

    Arguments:
        line: The line the column indexes.
        byte_column: Byte offset into `line`; clamped to its length.
    """
    limit := byte_column if byte_column < line.length else line.length
    if limit <= 0
        return 0
    end
    units := 0
    i := 0
    while i < limit
        lead := line.byte_at(i)
        units = units + _utf16_units(lead)
        i = i + _utf8_sequence_length(lead)
    end
    return units
end


def utf16_to_byte_column(line: string, utf16_column: integer) -> integer
    """A `Position.character` measured in UTF-16 code units, as a byte offset
    into `line`.

    A column past the end of the line clamps to its length, which is what an
    editor sends when its view is ahead of the buffer.

    Arguments:
        line: The line the column indexes.
        utf16_column: UTF-16 code unit offset into `line`.
    """
    if utf16_column <= 0
        return 0
    end
    units := 0
    i := 0
    while i < line.length and units < utf16_column
        lead := line.byte_at(i)
        units = units + _utf16_units(lead)
        i = i + _utf8_sequence_length(lead)
    end
    return i if i < line.length else line.length
end


def private _utf8_sequence_length(lead: integer) -> integer
    """How many bytes the UTF-8 character introduced by `lead` occupies. A
    stray continuation byte counts as one so a malformed line still advances.
    """
    if lead < CONT_MIN
        return 1
    end
    if lead < THREE_MIN
        return 2
    end
    return 3 if lead < FOUR_MIN else 4
end


def private _utf16_units(lead: integer) -> integer
    """How many UTF-16 code units the character introduced by `lead` encodes
    to: two for the astral plane (a surrogate pair), one otherwise.
    """
    return 2 if lead >= FOUR_MIN else 1
end
