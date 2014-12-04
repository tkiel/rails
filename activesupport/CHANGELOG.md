*   Added `#verified` and `#valid_message?` methods to `ActiveSupport::MessageVerifier`

    Previously, the only way to decode a message with `ActiveSupport::MessageVerifier` was to use `#verify`, which would raise an exception on invalid messages. Now `#verified` can also be used, which returns `nil` on messages that cannot be decoded.

    Previously, there was no way to check if a message's format was valid without attempting to decode it. `#valid_message?` is a boolean convenience method that checks whether the message is valid without actually decoding it.

    *Logan Leger*

Please check [4-2-stable](https://github.com/rails/rails/blob/4-2-stable/activesupport/CHANGELOG.md) for previous changes.
