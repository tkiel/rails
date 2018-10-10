# frozen_string_literal: true

module ActiveRecord
  module ConnectionHandling
    RAILS_ENV   = -> { (Rails.env if defined?(Rails.env)) || ENV["RAILS_ENV"].presence || ENV["RACK_ENV"].presence }
    DEFAULT_ENV = -> { RAILS_ENV.call || "default_env" }

    # Establishes the connection to the database. Accepts a hash as input where
    # the <tt>:adapter</tt> key must be specified with the name of a database adapter (in lower-case)
    # example for regular databases (MySQL, PostgreSQL, etc):
    #
    #   ActiveRecord::Base.establish_connection(
    #     adapter:  "mysql2",
    #     host:     "localhost",
    #     username: "myuser",
    #     password: "mypass",
    #     database: "somedatabase"
    #   )
    #
    # Example for SQLite database:
    #
    #   ActiveRecord::Base.establish_connection(
    #     adapter:  "sqlite3",
    #     database: "path/to/dbfile"
    #   )
    #
    # Also accepts keys as strings (for parsing from YAML for example):
    #
    #   ActiveRecord::Base.establish_connection(
    #     "adapter"  => "sqlite3",
    #     "database" => "path/to/dbfile"
    #   )
    #
    # Or a URL:
    #
    #   ActiveRecord::Base.establish_connection(
    #     "postgres://myuser:mypass@localhost/somedatabase"
    #   )
    #
    # In case {ActiveRecord::Base.configurations}[rdoc-ref:Core.configurations]
    # is set (Rails automatically loads the contents of config/database.yml into it),
    # a symbol can also be given as argument, representing a key in the
    # configuration hash:
    #
    #   ActiveRecord::Base.establish_connection(:production)
    #
    # The exceptions AdapterNotSpecified, AdapterNotFound and +ArgumentError+
    # may be returned on an error.
    def establish_connection(config_or_env = nil)
      config_hash = resolve_config_for_connection(config_or_env)
      connection_handler.establish_connection(config_hash)
    end

    # Connects a model to the databases specified. The +database+ keyword
    # takes a hash consisting of a +role+ and a +database_key+.
    #
    # This will create a connection handler for switching between connections,
    # look up the config hash using the +database_key+ and finally
    # establishes a connection to that config.
    #
    #   class AnimalsModel < ApplicationRecord
    #     self.abstract_class = true
    #
    #     connects_to database: { writing: :primary, reading: :primary_replica }
    #   end
    #
    # Returns an array of established connections.
    def connects_to(database: {})
      connections = []

      database.each do |role, database_key|
        config_hash = resolve_config_for_connection(database_key)
        handler = lookup_connection_handler(role.to_sym)

        connections << handler.establish_connection(config_hash)
      end

      connections
    end

    # Connects to a database or role (ex writing, reading, or another
    # custom role) for the duration of the block.
    #
    # If a role is passed, Active Record will look up the connection
    # based on the requested role:
    #
    #   ActiveRecord::Base.connected_to(role: :writing) do
    #     Dog.create! # creates dog using dog connection
    #   end
    #
    #   ActiveRecord::Base.connected_to(role: :reading) do
    #     Dog.create! # throws exception because we're on a replica
    #   end
    #
    #   ActiveRecord::Base.connected_to(role: :unknown_ode) do
    #     # raises exception due to non-existent role
    #   end
    #
    # For cases where you may want to connect to a database outside of the model,
    # you can use +connected_to+ with a +database+ argument. The +database+ argument
    # expects a symbol that corresponds to the database key in your config.
    #
    # This will connect to a new database for the queries inside the block.
    #
    #   ActiveRecord::Base.connected_to(database: :animals_slow_replica) do
    #     Dog.run_a_long_query # runs a long query while connected to the +animals_slow_replica+
    #   end
    def connected_to(database: nil, role: nil, &blk)
      if database && role
        raise ArgumentError, "connected_to can only accept a database or role argument, but not both arguments."
      elsif database
        config_hash = resolve_config_for_connection(database)
        handler = lookup_connection_handler(database.to_sym)

        with_handler(database.to_sym) do
          handler.establish_connection(config_hash)
          return yield
        end
      elsif role
        with_handler(role.to_sym, &blk)
      else
        raise ArgumentError, "must provide a `database` or a `role`."
      end
    end

    def lookup_connection_handler(handler_key) # :nodoc:
      connection_handlers[handler_key] ||= ActiveRecord::ConnectionAdapters::ConnectionHandler.new
    end

    def with_handler(handler_key, &blk) # :nodoc:
      handler = lookup_connection_handler(handler_key)
      swap_connection_handler(handler, &blk)
    end

    def resolve_config_for_connection(config_or_env) # :nodoc:
      raise "Anonymous class is not allowed." unless name

      config_or_env ||= DEFAULT_ENV.call.to_sym
      pool_name = self == Base ? "primary" : name
      self.connection_specification_name = pool_name

      resolver = ConnectionAdapters::ConnectionSpecification::Resolver.new(Base.configurations)
      config_hash = resolver.resolve(config_or_env, pool_name).symbolize_keys
      config_hash[:name] = pool_name

      config_hash
    end

    # Returns the connection currently associated with the class. This can
    # also be used to "borrow" the connection to do database work unrelated
    # to any of the specific Active Records.
    def connection
      retrieve_connection
    end

    attr_writer :connection_specification_name

    # Return the specification name from the current class or its parent.
    def connection_specification_name
      if !defined?(@connection_specification_name) || @connection_specification_name.nil?
        return self == Base ? "primary" : superclass.connection_specification_name
      end
      @connection_specification_name
    end

    # Returns the configuration of the associated connection as a hash:
    #
    #  ActiveRecord::Base.connection_config
    #  # => {pool: 5, timeout: 5000, database: "db/development.sqlite3", adapter: "sqlite3"}
    #
    # Please use only for reading.
    def connection_config
      connection_pool.spec.config
    end

    def connection_pool
      connection_handler.retrieve_connection_pool(connection_specification_name) || raise(ConnectionNotEstablished)
    end

    def retrieve_connection
      connection_handler.retrieve_connection(connection_specification_name)
    end

    # Returns +true+ if Active Record is connected.
    def connected?
      connection_handler.connected?(connection_specification_name)
    end

    def remove_connection(name = nil)
      name ||= @connection_specification_name if defined?(@connection_specification_name)
      # if removing a connection that has a pool, we reset the
      # connection_specification_name so it will use the parent
      # pool.
      if connection_handler.retrieve_connection_pool(name)
        self.connection_specification_name = nil
      end

      connection_handler.remove_connection(name)
    end

    def clear_cache! # :nodoc:
      connection.schema_cache.clear!
    end

    delegate :clear_active_connections!, :clear_reloadable_connections!,
      :clear_all_connections!, :flush_idle_connections!, to: :connection_handler

    private

      def swap_connection_handler(handler, &blk) # :nodoc:
        old_handler, ActiveRecord::Base.connection_handler = ActiveRecord::Base.connection_handler, handler
        yield
      ensure
        ActiveRecord::Base.connection_handler = old_handler
      end
  end
end
