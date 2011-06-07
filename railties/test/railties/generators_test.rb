RAILS_ISOLATION_COMMAND = "engine"
require "isolation/abstract_unit"

require "#{RAILS_FRAMEWORK_ROOT}/railties/lib/rails/generators/test_case"

module RailtiesTests
  class GeneratorTest < Rails::Generators::TestCase
    include ActiveSupport::Testing::Isolation

    TMP_PATH = File.expand_path(File.join(File.dirname(__FILE__), *%w[.. .. tmp]))
    self.destination_root = File.join(TMP_PATH, "foo_bar")

    def tmp_path(*args)
      File.join(TMP_PATH, *args)
    end

    def engine_path
      tmp_path('foo_bar')
    end

    def bundled_rails(cmd)
      `bundle exec rails #{cmd}`
    end

    def rails(cmd)
      environment = File.expand_path('../../../../load_paths', __FILE__)
      if File.exist?("#{environment}.rb")
        require_environment = "-r #{environment}"
      end
      `#{Gem.ruby} #{require_environment} #{RAILS_FRAMEWORK_ROOT}/bin/rails #{cmd}`
    end

    def build_engine
      FileUtils.mkdir_p(engine_path)
      FileUtils.rm_r(engine_path)

      rails("plugin new #{engine_path} --full --mountable")

      Dir.chdir(engine_path) do
        File.open("Gemfile", "w") do |f|
          f.write <<-GEMFILE.gsub(/^ {12}/, '')
            source "http://rubygems.org"

            gem 'rails', :path => '#{RAILS_FRAMEWORK_ROOT}'
            gem 'sqlite3'

            if RUBY_VERSION < '1.9'
              gem "ruby-debug", ">= 0.10.3"
            end
          GEMFILE
        end
      end
    end

    def setup
      build_engine
    end

    def test_controllers_are_correctly_namespaced
      Dir.chdir(engine_path) do
        bundled_rails("g controller topics")
        assert_file "app/controllers/foo_bar/topics_controller.rb", /FooBar::TopicsController/
        assert_no_file "app/controllers/topics_controller.rb"
      end
    end

    def test_models_are_correctly_namespaced
      Dir.chdir(engine_path) do
        bundled_rails("g model topic")
        assert_file "app/models/foo_bar/topic.rb", /FooBar::Topic/
        assert_no_file "app/models/topic.rb"
      end
    end

    def test_helpers_are_correctly_namespaced
      Dir.chdir(engine_path) do
        bundled_rails("g helper topics")
        assert_file "app/helpers/foo_bar/topics_helper.rb", /FooBar::TopicsHelper/
        assert_no_file "app/helpers/topics_helper.rb"
      end
    end
  end
end
