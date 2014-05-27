*   Deprecate all *_filter callbacks in favor of *_action callbacks.

    *Rafael Mendonça França*

*   Fix URL generation with `:trailing_slash` such that it does not add
    a trailing slash after `.:format`

    *Dan Langevin*

*   Build full URI as string when processing path in integration tests for
    performance reasons.

    *Guo Xiang Tan*

*   Fix `'Stack level too deep'` when rendering `head :ok` in an action method
    called 'status' in a controller.

    Fixes #13905.

    *Christiaan Van den Poel*

*   Add MKCALENDAR HTTP method (RFC 4791).

    *Sergey Karpesh*

*   Instrument fragment cache metrics.

    Adds `:controller`: and `:action` keys to the instrumentation payload
    for the `*_fragment.action_controller` notifications. This allows tracking
    e.g. the fragment cache hit rates for each controller action.

    *Daniel Schierbeck*

*   Always use the provided port if the protocol is relative.

    Fixes #15043.

    *Guilherme Cavalcanti*, *Andrew White*

*   Moved `params[request_forgery_protection_token]` into its own method
    and improved tests.

    Fixes #11316.

    *Tom Kadwill*

*   Added verification of route constraints given as a Proc or an object responding
    to `:matches?`. Previously, when given an non-complying object, it would just
    silently fail to enforce the constraint. It will now raise an `ArgumentError`
    when setting up the routes.

    *Xavier Defrang*

*   Properly treat the entire IPv6 User Local Address space as private for
    purposes of remote IP detection. Also handle uppercase private IPv6
    addresses.

    Fixes #12638.

    *Caleb Spare*

*   Fixed an issue with migrating legacy json cookies.

    Previously, the `VerifyAndUpgradeLegacySignedMessage` assumes all incoming
    cookies are marshal-encoded. This is not the case when `secret_token` is
    used in conjunction with the `:json` or `:hybrid` serializer.

    In those case, when upgrading to use `secret_key_base`, this would cause a
    `TypeError: incompatible marshal file format` and a 500 error for the user.

    Fixes #14774.

    *Godfrey Chan*

*   Make URL escaping more consistent:

    1. Escape '%' characters in URLs - only unescaped data should be passed to URL helpers
    2. Add an `escape_segment` helper to `Router::Utils` that escapes '/' characters
    3. Use `escape_segment` rather than `escape_fragment` in optimized URL generation
    4. Use `escape_segment` rather than `escape_path` in URL generation

    For point 4 there are two exceptions. Firstly, when a route uses wildcard segments
    (e.g. `*foo`) then we use `escape_path` as the value may contain '/' characters. This
    means that wildcard routes can't be optimized. Secondly, if a `:controller` segment
    is used in the path then this uses `escape_path` as the controller may be namespaced.

    Fixes #14629, #14636 and #14070.

    *Andrew White*, *Edho Arief*

*   Add alias `ActionDispatch::Http::UploadedFile#to_io` to
    `ActionDispatch::Http::UploadedFile#tempfile`.

    *Tim Linquist*

*   Returns null type format when format is not know and controller is using `any`
    format block.

    Fixes #14462.

    *Rafael Mendonça França*

*   Improve routing error page with fuzzy matching search.

    *Winston*

*   Only make deeply nested routes shallow when parent is shallow.

    Fixes #14684.

    *Andrew White*, *James Coglan*

*   Append link to bad code to backtrace when exception is `SyntaxError`.

    *Boris Kuznetsov*

*   Swapped the parameters of assert_equal in `assert_select` so that the
    proper values were printed correctly

    Fixes #14422.

    *Vishal Lal*

*   The method `shallow?` returns false if the parent resource is a singleton so
    we need to check if we're not inside a nested scope before copying the :path
    and :as options to their shallow equivalents.

    Fixes #14388.

    *Andrew White*

*   Make logging of CSRF failures optional (but on by default) with the
    `log_warning_on_csrf_failure` configuration setting in
    `ActionController::RequestForgeryProtection`.

    *John Barton*

*   Fix URL generation in controller tests with request-dependent
    `default_url_options` methods.

    *Tony Wooster*


Please check [4-1-stable](https://github.com/rails/rails/blob/4-1-stable/actionpack/CHANGELOG.md) for previous changes.
