"""JSON construction helpers shared by the SDK's `__dict` methods.

A JSON object is a native `dict[string, Any]` and an array a `list[Any]`, so the
`__dict` methods across the SDK build those directly and hand them to
`json.encode` for the wire form. The helper here centralizes the "omit an
optional field when unset" convention the spec expects.
"""


def put_str(obj: dict[string, Any], key: string, value: string) -> none
    """Insert `key -> value` as a JSON string, but only when `value` is
    non-empty. Used by `__dict` methods to omit unset optional string fields
    rather than emitting `""`.
    """
    if value != ""
        obj[key] = value
    end
end
