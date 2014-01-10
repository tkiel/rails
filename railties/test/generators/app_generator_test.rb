require 'generators/generators_test_helper'
require 'rails/generators/rails/app/app_generator'
require 'generators/shared_generator_tests'

DEFAULT_APP_FILES = %w(
  .gitignore
  README.rdoc
  Gemfile
  Rakefile
  config.ru
  app/assets/javascripts
  app/assets/stylesheets
  app/assets/images
  app/controllers
  app/controllers/concerns
  app/helpers
  app/mailers
  app/models
  app/models/concerns
  app/views/layouts
  bin/bundle
  bin/rails
  bin/rake
  config/environments
  config/initializers
  config/locales
  db
  lib
  lib/tasks
  lib/assets
  log
  test/test_helper.rb
  test/fixtures
  test/controllers
  test/models
  test/helpers
  test/mailers
  test/integration
  vendor
  vendor/assets
  vendor/assets/stylesheets
  vendor/assets/javascripts
  tmp/cache
  tmp/cache/assets
)

class AppGeneratorTest < Rails::Generators::TestCase
  include GeneratorsTestHelper
  arguments [destination_root]

  # brings setup, teardown, and some tests
  include SharedGeneratorTests

  def default_files
    ::DEFAULT_APP_FILES
  end

  def test_assets
    run_generator

    assert_file("app/views/layouts/application.html.erb", /stylesheet_link_tag\s+"application", media: "all", "data-turbolinks-track" => true/)
    assert_file("app/views/layouts/application.html.erb", /javascript_include_tag\s+"application", "data-turbolinks-track" => true/)
    assert_file("app/assets/stylesheets/application.css")
    assert_file("app/assets/javascripts/application.js")
  end

  def test_invalid_application_name_raises_an_error
    content = capture(:stderr){ run_generator [File.join(destination_root, "43-things")] }
    assert_equal "Invalid application name 43-things. Please give a name which does not start with numbers.\n", content
  end

  def test_invalid_application_name_is_fixed
    run_generator [File.join(destination_root, "things-43")]
    assert_file "things-43/config/environment.rb", /Rails\.application\.initialize!/
    assert_file "things-43/config/application.rb", /^module Things43$/
  end

  def test_application_new_exits_with_non_zero_code_on_invalid_application_name
    quietly { system 'rails new test --no-rc' }
    assert_equal false, $?.success?
  end

  def test_application_new_exits_with_message_and_non_zero_code_when_generating_inside_existing_rails_directory
    app_root = File.join(destination_root, 'myfirstapp')
    run_generator [app_root]
    output = nil
    Dir.chdir(app_root) do
      output = `rails new mysecondapp`
    end
    assert_equal "Can't initialize a new Rails application within the directory of another, please change to a non-Rails directory first.\nType 'rails' for help.\n", output
    assert_equal false, $?.success?
  end

  def test_application_new_show_help_message_inside_existing_rails_directory
    app_root = File.join(destination_root, 'myfirstapp')
    run_generator [app_root]
    output = Dir.chdir(app_root) do
      `rails new --help`
    end
    assert_match(/rails new APP_PATH \[options\]/, output)
    assert_equal true, $?.success?
  end

  def test_application_name_is_detected_if_it_exists_and_app_folder_renamed
    app_root       = File.join(destination_root, "myapp")
    app_moved_root = File.join(destination_root, "myapp_moved")

    run_generator [app_root]

    Rails.application.config.root = app_moved_root
    Rails.application.class.stubs(:name).returns("Myapp")
    Rails.application.stubs(:is_a?).returns(Rails::Application)

    FileUtils.mv(app_root, app_moved_root)

    # make sure we are in correct dir
    FileUtils.cd(app_moved_root)

    generator = Rails::Generators::AppGenerator.new ["rails"], { with_dispatchers: true },
                                                               destination_root: app_moved_root, shell: @shell
    generator.send(:app_const)
    quietly { generator.send(:create_config_files) }
    assert_file "myapp_moved/config/environment.rb", /Rails\.application\.initialize!/
    assert_file "myapp_moved/config/initializers/session_store.rb", /_myapp_session/
  end

  def test_rails_update_generates_correct_session_key
    app_root = File.join(destination_root, 'myapp')
    run_generator [app_root]

    Rails.application.config.root = app_root
    Rails.application.class.stubs(:name).returns("Myapp")
    Rails.application.stubs(:is_a?).returns(Rails::Application)

    generator = Rails::Generators::AppGenerator.new ["rails"], { with_dispatchers: true }, destination_root: app_root, shell: @shell
    generator.send(:app_const)
    quietly { generator.send(:create_config_files) }
    assert_file "myapp/config/initializers/session_store.rb", /_myapp_session/
  end

  def test_application_names_are_not_singularized
    run_generator [File.join(destination_root, "hats")]
    assert_file "hats/config/environment.rb", /Rails\.application\.initialize!/
  end

  def test_gemfile_has_no_whitespace_errors
    run_generator
    absolute = File.expand_path("Gemfile", destination_root)
    File.open(absolute, 'r') do |f|
      f.each_line do |line|
        assert_no_match %r{/^[ \t]+$/}, line
      end
    end
  end

  def test_config_database_is_added_by_default
    run_generator
    assert_file "config/database.yml", /sqlite3/
    unless defined?(JRUBY_VERSION)
      assert_gem "sqlite3"
    else
      assert_gem "activerecord-jdbcsqlite3-adapter"
    end
  end

  def test_arbitrary_code
    output = Tempfile.open('my_template') do |template|
      template.puts 'puts "You are using Rails version #{Rails::VERSION::STRING}."'
      template.close
      run_generator([destination_root, "-m", template.path])
    end
    assert_match 'You are using', output
  end

  def test_add_gemfile_entry
    Tempfile.open('my_template') do |template|
      template.puts 'gemfile_entry "tenderlove"'
      template.flush
      template.close
      run_generator([destination_root, "-n", template.path])
      assert_file "Gemfile", /tenderlove/
    end
  end

  def test_add_skip_entry
    Tempfile.open 'my_template' do |template|
      template.puts 'add_gem_entry_filter { |gem| gem.name != "jbuilder" }'
      template.close

      run_generator([destination_root, "-n", template.path])
      assert_file "Gemfile" do |contents|
        assert_no_match 'jbuilder', contents
      end
    end
  end

  def test_remove_gem
    Tempfile.open 'my_template' do |template|
      template.puts 'remove_gem "jbuilder"'
      template.close

      run_generator([destination_root, "-n", template.path])
      assert_file "Gemfile" do |contents|
        assert_no_match 'jbuilder', contents
      end
    end
  end

  def test_skip_turbolinks_when_it_is_not_on_gemfile
    Tempfile.open 'my_template' do |template|
      template.puts 'add_gem_entry_filter { |gem| gem.name != "turbolinks" }'
      template.flush

      run_generator([destination_root, "-n", template.path])
      assert_file "Gemfile" do |contents|
        assert_no_match 'turbolinks', contents
      end

      assert_file "app/views/layouts/application.html.erb" do |contents|
        assert_no_match 'turbolinks', contents
      end

      assert_file "app/views/layouts/application.html.erb" do |contents|
        assert_no_match('data-turbolinks-track', contents)
      end

      assert_file "app/assets/javascripts/application.js" do |contents|
        assert_no_match 'turbolinks', contents
      end
    end
  end

  def test_config_another_database
    run_generator([destination_root, "-d", "mysql"])
    assert_file "config/database.yml", /mysql/
    unless defined?(JRUBY_VERSION)
      assert_gem "mysql2"
    else
      assert_gem "activerecord-jdbcmysql-adapter"
    end
  end

  def test_config_database_app_name_with_period
    run_generator [File.join(destination_root, "common.usage.com"), "-d", "postgresql"]
    assert_file "common.usage.com/config/database.yml", /common_usage_com/
  end

  def test_config_postgresql_database
    run_generator([destination_root, "-d", "postgresql"])
    assert_file "config/database.yml", /postgresql/
    unless defined?(JRUBY_VERSION)
      assert_gem "pg"
    else
      assert_gem "activerecord-jdbcpostgresql-adapter"
    end
  end

  def test_config_jdbcmysql_database
    run_generator([destination_root, "-d", "jdbcmysql"])
    assert_file "config/database.yml", /mysql/
    assert_gem "activerecord-jdbcmysql-adapter"
  end

  def test_config_jdbcsqlite3_database
    run_generator([destination_root, "-d", "jdbcsqlite3"])
    assert_file "config/database.yml", /sqlite3/
    assert_gem "activerecord-jdbcsqlite3-adapter"
  end

  def test_config_jdbcpostgresql_database
    run_generator([destination_root, "-d", "jdbcpostgresql"])
    assert_file "config/database.yml", /postgresql/
    assert_gem "activerecord-jdbcpostgresql-adapter"
  end

  def test_config_jdbc_database
    run_generator([destination_root, "-d", "jdbc"])
    assert_file "config/database.yml", /jdbc/
    assert_file "config/database.yml", /mssql/
    assert_gem "activerecord-jdbc-adapter"
  end

  def test_config_jdbc_database_when_no_option_given
    if defined?(JRUBY_VERSION)
      run_generator([destination_root])
      assert_file "config/database.yml", /sqlite3/
      assert_gem "activerecord-jdbcsqlite3-adapter"
    end
  end

  def test_generator_if_skip_active_record_is_given
    run_generator [destination_root, "--skip-active-record"]
    assert_no_file "config/database.yml"
    assert_file "config/application.rb", /#\s+require\s+["']active_record\/railtie["']/
    assert_file "test/test_helper.rb" do |helper_content|
      assert_no_match(/fixtures :all/, helper_content)
    end
  end

  def test_generator_if_skip_action_view_is_given
    run_generator [destination_root, "--skip-action-view"]
    assert_file "config/application.rb", /#\s+require\s+["']action_view\/railtie["']/
  end

  def test_generator_if_skip_sprockets_is_given
    run_generator [destination_root, "--skip-sprockets"]
    assert_file "config/application.rb" do |content|
      assert_match(/#\s+require\s+["']sprockets\/railtie["']/, content)
    end
    assert_file "Gemfile" do |content|
      assert_no_match(/sass-rails/, content)
      assert_no_match(/uglifier/, content)
      assert_match(/coffee-rails/, content)
    end
    assert_file "config/environments/development.rb" do |content|
      assert_no_match(/config\.assets\.debug = true/, content)
    end
    assert_file "config/environments/production.rb" do |content|
      assert_no_match(/config\.assets\.digest = true/, content)
      assert_no_match(/config\.assets\.js_compressor = :uglifier/, content)
      assert_no_match(/config\.assets\.css_compressor = :sass/, content)
      assert_no_match(/config\.assets\.version = '1\.0'/, content)
    end
  end

  def test_inclusion_of_javascript_runtime
    run_generator([destination_root])
    if defined?(JRUBY_VERSION)
      assert_gem "therubyrhino"
    else
      assert_file "Gemfile", /# gem\s+["']therubyracer["']+, \s+platforms: :ruby$/
    end
  end

  def test_inclusion_of_plateform_dependent_gems
    run_generator([destination_root])
    if RUBY_ENGINE == 'rbx'
      assert_gem 'rubysl'
    end
  end

  def test_jquery_is_the_default_javascript_library
    run_generator
    assert_file "app/assets/javascripts/application.js" do |contents|
      assert_match %r{^//= require jquery}, contents
      assert_match %r{^//= require jquery_ujs}, contents
    end
    assert_gem "jquery-rails"
  end

  def test_other_javascript_libraries
    run_generator [destination_root, '-j', 'prototype']
    assert_file "app/assets/javascripts/application.js" do |contents|
      assert_match %r{^//= require prototype}, contents
      assert_match %r{^//= require prototype_ujs}, contents
    end
    assert_gem "prototype-rails"
  end

  def test_javascript_is_skipped_if_required
    run_generator [destination_root, "--skip-javascript"]

    assert_no_file "app/assets/javascripts"
    assert_no_file "vendor/assets/javascripts"

    assert_file "app/views/layouts/application.html.erb" do |contents|
      assert_match(/stylesheet_link_tag\s+"application", media: "all" %>/, contents)
      assert_no_match(/javascript_include_tag\s+"application" \%>/, contents)
    end

    assert_file "Gemfile" do |content|
      assert_no_match(/coffee-rails/, content)
      assert_no_match(/jquery-rails/, content)
    end
  end

  def test_inclusion_of_jbuilder
    run_generator
    assert_file "Gemfile", /gem 'jbuilder'/
  end

  def test_inclusion_of_debugger
    run_generator
    if defined?(JRUBY_VERSION)
      assert_file "Gemfile" do |content|
        assert_no_match(/debugger/, content)
      end
    else
      assert_file "Gemfile", /# gem 'debugger'/
    end
  end

  def test_inclusion_of_lazy_loaded_sdoc
    run_generator
    assert_file 'Gemfile', /gem 'sdoc', \s+group: :doc, require: false/
  end

  def test_template_from_dir_pwd
    FileUtils.cd(Rails.root)
    assert_match(/It works from file!/, run_generator([destination_root, "-m", "lib/template.rb"]))
  end

  def test_usage_read_from_file
    File.expects(:read).returns("USAGE FROM FILE")
    assert_equal "USAGE FROM FILE", Rails::Generators::AppGenerator.desc
  end

  def test_default_usage
    Rails::Generators::AppGenerator.expects(:usage_path).returns(nil)
    assert_match(/Create rails files for app generator/, Rails::Generators::AppGenerator.desc)
  end

  def test_default_namespace
    assert_match "rails:app", Rails::Generators::AppGenerator.namespace
  end

  def test_file_is_added_for_backwards_compatibility
    action :file, 'lib/test_file.rb', 'heres test data'
    assert_file 'lib/test_file.rb', 'heres test data'
  end

  def test_test_unit_is_removed_from_frameworks_if_skip_test_unit_is_given
    run_generator [destination_root, "--skip-test-unit"]
    assert_file "config/application.rb", /#\s+require\s+["']rails\/test_unit\/railtie["']/
  end

  def test_no_active_record_or_test_unit_if_skips_given
    run_generator [destination_root, "--skip-test-unit", "--skip-active-record"]
    assert_file "config/application.rb", /#\s+require\s+["']rails\/test_unit\/railtie["']/
    assert_file "config/application.rb", /#\s+require\s+["']active_record\/railtie["']/
  end

  def test_new_hash_style
    run_generator [destination_root]
    assert_file "config/initializers/session_store.rb" do |file|
      assert_match(/config.session_store :cookie_store, key: '_.+_session'/, file)
    end
  end

  def test_pretend_option
    output = run_generator [File.join(destination_root, "myapp"), "--pretend"]
    assert_no_match(/run  bundle install/, output)
  end

  def test_application_name_with_spaces
    path = File.join(destination_root, "foo bar".shellescape)

    # This also applies to MySQL apps but not with SQLite
    run_generator [path, "-d", 'postgresql']

    assert_file "foo bar/config/database.yml", /database: foo_bar_development/
    assert_file "foo bar/config/initializers/session_store.rb", /key: '_foo_bar/
  end

  def test_spring
    run_generator
    assert_file "Gemfile", /gem 'spring', \s+group: :development/
  end

  def test_spring_binstubs
    generator.stubs(:bundle_command).with('install')
    generator.expects(:bundle_command).with('exec spring binstub --all').once
    quietly { generator.invoke_all }
  end

  def test_spring_no_fork
    Process.stubs(:respond_to?).with(:fork).returns(false)
    run_generator

    assert_file "Gemfile" do |content|
      assert_no_match(/spring/, content)
    end
  end

  def test_skip_spring
    run_generator [destination_root, "--skip-spring"]

    assert_file "Gemfile" do |content|
      assert_no_match(/spring/, content)
    end
  end

protected

  def action(*args, &block)
    silence(:stdout) { generator.send(*args, &block) }
  end

  def assert_gem(gem)
    assert_file "Gemfile", /^gem\s+["']#{gem}["']$/
  end
end
