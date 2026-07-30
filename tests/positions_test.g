"""Position-encoding tests: what the client is offered, and the byte ↔ UTF-16
column conversion applied at the protocol boundary.

The sample lines mix one-, two-, three-, and four-byte characters, since each
costs a different number of bytes and the last is the only one costing two
UTF-16 code units.
"""


use testing

use (
    ENCODING_UTF16,
    ENCODING_UTF8,
    byte_to_utf16_column,
    is_ascii_only,
    negotiate_position_encoding,
    utf16_to_byte_column,
) from lsp_sdk

# "café" — the accented vowel is two bytes, so the line is five bytes long and
# four UTF-16 code units.


TWO_BYTE_LINE: constant[string] = "café ok"

# A grinning face is four bytes and a surrogate pair: two UTF-16 code units.


FOUR_BYTE_LINE: constant[string] = "x 😀 y"

# A euro sign is three bytes and one UTF-16 code unit.


THREE_BYTE_LINE: constant[string] = "€10"


def private offering(encodings: list[Any]) -> Any
    """Client capabilities offering `encodings` under `general`."""
    general: dict[string, Any] = {"positionEncodings": encodings}
    caps: dict[string, Any] = {"general": general}
    return caps
end


@test
def negotiation_prefers_utf8_when_offered(t: testing.T) -> none
    caps := offering(["utf-16", "utf-8"])
    testing.assert_str(
        negotiate_position_encoding(caps),
        ENCODING_UTF8,
        "utf-8 wins wherever it appears",
    )
end


@test
def negotiation_falls_back_to_utf16(t: testing.T) -> none
    testing.assert_str(
        negotiate_position_encoding(offering(["utf-16", "utf-32"])),
        ENCODING_UTF16,
        "no utf-8 on offer",
    )
    testing.assert_str(
        negotiate_position_encoding(offering([] as list[Any])),
        ENCODING_UTF16,
        "an empty offer",
    )
    testing.assert_str(
        negotiate_position_encoding(none),
        ENCODING_UTF16,
        "a client that sent no capabilities",
    )
end


@test
def ascii_detection_separates_the_common_case(t: testing.T) -> none
    testing.assert_true(is_ascii_only("plain ascii"), "an ASCII line")
    testing.assert_false(is_ascii_only(TWO_BYTE_LINE), "a line with an accent")
end


@test
def ascii_columns_are_unchanged_in_both_directions(t: testing.T) -> none
    line := "def main() -> none"
    testing.assert_int(byte_to_utf16_column(line, 4), 4, "byte to utf-16 on ASCII")
    testing.assert_int(utf16_to_byte_column(line, 4), 4, "utf-16 to byte on ASCII")
end


@test
def two_byte_characters_shift_the_column(t: testing.T) -> none
    # "café ok": bytes c-a-f-é(2)-space-o-k; the space is byte 5, unit 4.
    testing.assert_int(byte_to_utf16_column(TWO_BYTE_LINE, 5), 4, "column after the accent")
    testing.assert_int(utf16_to_byte_column(TWO_BYTE_LINE, 4), 5, "and back")
end


@test
def three_byte_characters_cost_one_unit(t: testing.T) -> none
    testing.assert_int(byte_to_utf16_column(THREE_BYTE_LINE, 3), 1, "after the euro sign")
    testing.assert_int(utf16_to_byte_column(THREE_BYTE_LINE, 1), 3, "and back")
end


@test
def astral_characters_cost_two_units(t: testing.T) -> none
    # "x 😀 y": the emoji occupies bytes 2..5 and units 2..3.
    testing.assert_int(byte_to_utf16_column(FOUR_BYTE_LINE, 6), 4, "column after the emoji")
    testing.assert_int(utf16_to_byte_column(FOUR_BYTE_LINE, 4), 6, "and back")
end


@test
def columns_past_the_line_clamp_to_its_length(t: testing.T) -> none
    line := "short"
    testing.assert_int(byte_to_utf16_column(line, 99), 5, "byte column past the end")
    testing.assert_int(utf16_to_byte_column(line, 99), 5, "utf-16 column past the end")
end


@test
def a_zero_column_stays_zero(t: testing.T) -> none
    testing.assert_int(byte_to_utf16_column(TWO_BYTE_LINE, 0), 0, "byte column zero")
    testing.assert_int(utf16_to_byte_column(TWO_BYTE_LINE, 0), 0, "utf-16 column zero")
end


@test
def conversion_round_trips_at_every_boundary(t: testing.T) -> none
    line := TWO_BYTE_LINE
    units := byte_to_utf16_column(line, line.length)
    for u in range(units + 1)
        b := utf16_to_byte_column(line, u)
        testing.assert_int(byte_to_utf16_column(line, b), u, f"round trip at unit {u}")
    end
end
