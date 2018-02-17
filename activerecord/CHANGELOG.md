## Rails 6.0.0.alpha (Unreleased) ##

*   Rails 6 requires Ruby 2.4.1 or newer.

    *Jeremy Daer*

*   Deprecate `update_attributes`/`!` in favor of `update`/`!`.

    *Eddie Lebow*

*   Add ActiveRecord::Base.create_or_find_by/! to deal with the SELECT/INSERT race condition in
    ActiveRecord::Base.find_or_create_by/! by leaning on unique constraints in the database.

    *DHH*


Please check [5-2-stable](https://github.com/rails/rails/blob/5-2-stable/activerecord/CHANGELOG.md) for previous changes.
