*   ActiveRecord::Base.configurations now returns an object.

    ActiveRecord::Base.configurations used to return a hash, but this
    is an inflexible data model. In order to improve multiple-database
    handling in Rails, we've changed this to return an object. Some methods
    are provided to make the object behave hash-like in order to ease the
    transition process. Since most applications don't manipulate the hash
    we've decided to add backwards-compatible functionality that will throw
    a deprecation warning if used, however calling `ActiveRecord::Base.configurations`
    will use the new version internally and externally.

    For example, the following database.yml...

    ```
    development:
      adapter: sqlite3
      database: db/development.sqlite3
    ```

    Used to become a hash:

    ```
    { "development" => { "adapter" => "sqlite3", "database" => "db/development.sqlite3" } }
    ```

    Is now converted into the following object:

    ```
    #<ActiveRecord::DatabaseConfigurations:0x00007fd1acbdf800 @configurations=[
      #<ActiveRecord::DatabaseConfigurations::HashConfig:0x00007fd1acbded10 @env_name="development",
        @spec_name="primary", @config={"adapter"=>"sqlite3", "database"=>"db/development.sqlite3"}>
      ]
    ```

    Iterating over the database configurations has also changed. Instead of
    calling hash methods on the `configurations` hash directly, a new method `configs_for` has
    been provided that allows you to select the correct configuration. `env_name` is a required
    argument, `spec_name` is optional as well as passing a block. These return an array of
    database config objects for the requested environment and specification name respectively.

    ```
    ActiveRecord::Base.configurations.configs_for("development")
    ActiveRecord::Base.configurations.configs_for("development", "primary")
    ```

    *Eileen M. Uchitelle*, *Aaron Patterson*

*   Add database configuration to disable advisory locks.

    ```
    production:
      adapter: postgresql
      advisory_locks: false
    ```

    *Guo Xiang*

*   SQLite3 adapter `alter_table` method restores foreign keys.

    *Yasuo Honda*

*   Allow `:to_table` option to `invert_remove_foreign_key`.

    Example:

       remove_foreign_key :accounts, to_table: :owners

    *Nikolay Epifanov*, *Rich Chen*

*   Add environment & load_config dependency to `bin/rake db:seed` to enable
    seed load in environments without Rails and custom DB configuration

    *Tobias Bielohlawek*

*   Fix default value for mysql time types with specified precision.

    *Nikolay Kondratyev*

*   Fix `touch` option to behave consistently with `Persistence#touch` method.

    *Ryuta Kamizono*

*   Migrations raise when duplicate column definition.

    Fixes #33024.

    *Federico Martinez*

*   Bump minimum SQLite version to 3.8

    *Yasuo Honda*

*   Fix parent record should not get saved with duplicate children records.

    Fixes #32940.

    *Santosh Wadghule*

*   Fix logic on disabling commit callbacks so they are not called unexpectedly when errors occur.

    *Brian Durand*

*   Ensure `Associations::CollectionAssociation#size` and `Associations::CollectionAssociation#empty?`
    use loaded association ids if present.

    *Graham Turner*

*   Add support to preload associations of polymorphic associations when not all the records have the requested associations.

    *Dana Sherson*

*   Add `touch_all` method to `ActiveRecord::Relation`.

    Example:

        Person.where(name: "David").touch_all(time: Time.new(2020, 5, 16, 0, 0, 0))

    *fatkodima*, *duggiefresh*

*   Add `ActiveRecord::Base.base_class?` predicate.

    *Bogdan Gusiev*

*   Add custom prefix/suffix options to `ActiveRecord::Store.store_accessor`.

    *Tan Huynh*, *Yukio Mizuta*

*   Rails 6 requires Ruby 2.4.1 or newer.

    *Jeremy Daer*

*   Deprecate `update_attributes`/`!` in favor of `update`/`!`.

    *Eddie Lebow*

*   Add ActiveRecord::Base.create_or_find_by/! to deal with the SELECT/INSERT race condition in
    ActiveRecord::Base.find_or_create_by/! by leaning on unique constraints in the database.

    *DHH*

*   Add `Relation#pick` as short-hand for single-value plucks.

    *DHH*


Please check [5-2-stable](https://github.com/rails/rails/blob/5-2-stable/activerecord/CHANGELOG.md) for previous changes.
