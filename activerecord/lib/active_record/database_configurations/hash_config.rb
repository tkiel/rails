# frozen_string_literal: true

module ActiveRecord
  class DatabaseConfigurations
    # A HashConfig object is created for each database configuration entry that
    # is created from a hash.
    #
    # A hash config:
    #
    #   { "development" => { "database" => "db_name" } }
    #
    # Becomes:
    #
    #   #<ActiveRecord::DatabaseConfigurations::HashConfig:0x00007fd1acbded10
    #     @env_name="development", @spec_name="primary", @config={"db_name"}>
    #
    # Options are:
    #
    # <tt>:env_name</tt> - The Rails environment, ie "development"
    # <tt>:spec_name</tt> - The specification name. In a standard two-tier
    # database configuration this will default to "primary". In a multiple
    # database three-tier database configuration this corresponds to the name
    # used in the second tier, for example "primary_readonly".
    # <tt>:config</tt> - The config hash. This is the hash that contains the
    # database adapter, name, and other important information for database
    # connections.
    class HashConfig < DatabaseConfig
      attr_reader :config

      def initialize(env_name, spec_name, config)
        super(env_name, spec_name)
        @config = config
      end

      def replica?
        config["replica"]
      end
    end
  end
end
