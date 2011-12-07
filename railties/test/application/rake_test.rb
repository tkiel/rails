# coding:utf-8
require "isolation/abstract_unit"

module ApplicationTests
  class RakeTest < Test::Unit::TestCase
    include ActiveSupport::Testing::Isolation

    def setup
      build_app
      boot_rails
      FileUtils.rm_rf("#{app_path}/config/environments")
    end

    def teardown
      teardown_app
    end

    def test_gems_tasks_are_loaded_first_than_application_ones
      app_file "lib/tasks/app.rake", <<-RUBY
        $task_loaded = Rake::Task.task_defined?("db:create:all")
      RUBY

      require "#{app_path}/config/environment"
      ::Rails.application.load_tasks
      assert $task_loaded
    end

    def test_environment_is_required_in_rake_tasks
      app_file "config/environment.rb", <<-RUBY
        SuperMiddleware = Struct.new(:app)

        AppTemplate::Application.configure do
          config.middleware.use SuperMiddleware
        end

        AppTemplate::Application.initialize!
      RUBY

      assert_match("SuperMiddleware", Dir.chdir(app_path){ `rake middleware` })
    end

    def test_initializers_are_executed_in_rake_tasks
      add_to_config <<-RUBY
        initializer "do_something" do
          puts "Doing something..."
        end

        rake_tasks do
          task :do_nothing => :environment do
          end
        end
      RUBY

      output = Dir.chdir(app_path){ `rake do_nothing` }
      assert_match "Doing something...", output
    end

    def test_code_statistics_sanity
      assert_match "Code LOC: 5     Test LOC: 0     Code to Test Ratio: 1:0.0",
        Dir.chdir(app_path){ `rake stats` }
    end

    def test_rake_test_error_output
      Dir.chdir(app_path){ `rake db:migrate` }

      app_file "config/database.yml", <<-RUBY
        development:
      RUBY

      app_file "test/unit/one_unit_test.rb", <<-RUBY
      RUBY

      app_file "test/functional/one_functional_test.rb", <<-RUBY
        raise RuntimeError
      RUBY

      app_file "test/integration/one_integration_test.rb", <<-RUBY
        raise RuntimeError
      RUBY

      silence_stderr do
        output = Dir.chdir(app_path){ `rake test` }
        assert_match(/Errors running test:units! #<ActiveRecord::AdapterNotSpecified/, output)
        assert_match(/Errors running test:functionals! #<RuntimeError/, output)
        assert_match(/Errors running test:integration! #<RuntimeError/, output)
      end
    end

    def test_rake_routes_calls_the_route_inspector
      app_file "config/routes.rb", <<-RUBY
        AppTemplate::Application.routes.draw do
          get '/cart', :to => 'cart#show'
        end
      RUBY
      assert_equal "cart GET /cart(.:format) cart#show\n", Dir.chdir(app_path){ `rake routes` }
    end

    def test_logger_is_flushed_when_exiting_production_rake_tasks
      add_to_config <<-RUBY
        rake_tasks do
          task :log_something => :environment do
            Rails.logger.error("Sample log message")
          end
        end
      RUBY

      output = Dir.chdir(app_path){ `rake log_something RAILS_ENV=production && cat log/production.log` }
      assert_match "Sample log message", output
    end

    def test_loading_specific_fixtures
      Dir.chdir(app_path) do
        `rails generate model user username:string password:string`
        `rails generate model product name:string`
        `rake db:migrate`
      end

      require "#{rails_root}/config/environment"

      # loading a specific fixture
      errormsg = Dir.chdir(app_path) { `rake db:fixtures:load FIXTURES=products` }
      assert $?.success?, errormsg

      assert_equal 2, ::AppTemplate::Application::Product.count
      assert_equal 0, ::AppTemplate::Application::User.count
    end

    def test_scaffold_tests_pass_by_default
      content = Dir.chdir(app_path) do
        `rails generate scaffold user username:string password:string`
        `bundle exec rake db:migrate db:test:clone test`
      end

      assert_match(/7 tests, 10 assertions, 0 failures, 0 errors/, content)
    end
  end
end
