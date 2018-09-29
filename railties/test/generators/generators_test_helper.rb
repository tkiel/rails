# frozen_string_literal: true

require "abstract_unit"
require "active_support/core_ext/module/remove_method"
require "active_support/testing/stream"
require "active_support/testing/method_call_assertions"
require "rails/generators"
require "rails/generators/test_case"

module Rails
  class << self
    remove_possible_method :root
    def root
      @root ||= Pathname.new(File.expand_path("../fixtures", __dir__))
    end
  end
end
Rails.application.config.root = Rails.root
Rails.application.config.generators.templates = [File.join(Rails.root, "lib", "templates")]

# Call configure to load the settings from
# Rails.application.config.generators to Rails::Generators
Rails.application.load_generators

require "active_record"
require "action_dispatch"
require "action_view"

module GeneratorsTestHelper
  include ActiveSupport::Testing::Stream
  include ActiveSupport::Testing::MethodCallAssertions

  def self.included(base)
    base.class_eval do
      destination File.join(Rails.root, "tmp")
      setup :prepare_destination

      begin
        base.tests Rails::Generators.const_get(base.name.sub(/Test$/, ""))
      rescue
      end
    end
  end

  def with_secondary_database_configuration
    original_configurations = ActiveRecord::Base.configurations
    ActiveRecord::Base.configurations = {
      test: {
        secondary: {
          database: "db/secondary.sqlite3",
          migrations_paths: "db/secondary_migrate",
        },
      },
    }
    yield
  ensure
    ActiveRecord::Base.configurations = original_configurations
  end

  def copy_routes
    routes = File.expand_path("../../lib/rails/generators/rails/app/templates/config/routes.rb.tt", __dir__)
    destination = File.join(destination_root, "config")
    FileUtils.mkdir_p(destination)
    FileUtils.cp routes, File.join(destination, "routes.rb")
  end
end
