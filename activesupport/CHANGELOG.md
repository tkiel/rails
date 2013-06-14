*   `HashWithIndifferentAccess#select` now returns a `HashWithIndifferentAccess`
    instance instead of a `Hash` instance.

    Fixes #10723

    *Albert Llop*

*   Add `DateTime#usec` and `DateTime#nsec` so that `ActiveSupport::TimeWithZone` keeps
    sub-second resolution when wrapping a `DateTime` value.

    Fixes #10855

    *Andrew White*

*   Fix `ActiveSupport::Dependencies::Loadable#load_dependency` calling
    `#blame_file!` on Exceptions that do not have the Blamable mixin

    *Andrew Kreiling*

*   Override `Time.at` to support the passing of Time-like values when called with a single argument.

    *Andrew White*

*   Prevent side effects to hashes inside arrays when
    `Hash#with_indifferent_access` is called.

    Fixes #10526

    *Yves Senn*

*   Raise an error when multiple `included` blocks are defined for a Concern.
    The old behavior would silently discard previously defined blocks, running
    only the last one.

    *Mike Dillon*

*   Replace `multi_json` with `json`.

    Since Rails requires Ruby 1.9 and since Ruby 1.9 includes `json` in the standard library,
    `multi_json` is no longer necessary.

    *Erik Michaels-Ober*

*   Added escaping of U+2028 and U+2029 inside the json encoder.
    These characters are legal in JSON but break the Javascript interpreter.
    After escaping them, the JSON is still legal and can be parsed by Javascript.

    *Mario Caropreso + Viktor Kelemen + zackham*

*   Fix skipping object callbacks using metadata fetched via callback chain
    inspection methods (`_*_callbacks`)

    *Sean Walbran*

*   Add a `fetch_multi` method to the cache stores. The method provides
    an easy to use API for fetching multiple values from the cache.

    Example:

        # Calculating scores is expensive, so we only do it for posts
        # that have been updated. Cache keys are automatically extracted
        # from objects that define a #cache_key method.
        scores = Rails.cache.fetch_multi(*posts) do |post|
          calculate_score(post)
        end

    *Daniel Schierbeck*

Please check [4-0-stable](https://github.com/rails/rails/blob/4-0-stable/activesupport/CHANGELOG.md) for previous changes.
