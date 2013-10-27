require 'digest/md5'
require 'securerandom'
require 'active_support/core_ext/string/strip'
require 'rails/version' unless defined?(Rails::VERSION)
require 'rbconfig'
require 'open-uri'
require 'uri'

module Rails
  module Generators
    class AppBase < Base # :nodoc:
      DATABASES = %w( mysql oracle postgresql sqlite3 frontbase ibm_db sqlserver )
      JDBC_DATABASES = %w( jdbcmysql jdbcsqlite3 jdbcpostgresql jdbc )
      DATABASES.concat(JDBC_DATABASES)

      attr_accessor :rails_template
      add_shebang_option!

      argument :app_path, type: :string

      def self.strict_args_position
        false
      end

      def self.add_shared_options_for(name)
        class_option :template,           type: :string, aliases: '-m',
                                          desc: "Path to some #{name} template (can be a filesystem path or URL)"

        class_option :skip_gemfile,       type: :boolean, default: false,
                                          desc: "Don't create a Gemfile"

        class_option :skip_bundle,        type: :boolean, aliases: '-B', default: false,
                                          desc: "Don't run bundle install"

        class_option :skip_git,           type: :boolean, aliases: '-G', default: false,
                                          desc: 'Skip .gitignore file'

        class_option :skip_keeps,         type: :boolean, default: false,
                                          desc: 'Skip source control .keep files'

        class_option :skip_active_record, type: :boolean, aliases: '-O', default: false,
                                          desc: 'Skip Active Record files'

        class_option :skip_action_view,   type: :boolean, aliases: '-V', default: false,
                                          desc: 'Skip Action View files'

        class_option :skip_sprockets,     type: :boolean, aliases: '-S', default: false,
                                          desc: 'Skip Sprockets files'

        class_option :database,           type: :string, aliases: '-d', default: 'sqlite3',
                                          desc: "Preconfigure for selected database (options: #{DATABASES.join('/')})"

        class_option :javascript,         type: :string, aliases: '-j', default: 'jquery',
                                          desc: 'Preconfigure for selected JavaScript library'

        class_option :skip_javascript,    type: :boolean, aliases: '-J', default: false,
                                          desc: 'Skip JavaScript files'

        class_option :dev,                type: :boolean, default: false,
                                          desc: "Setup the #{name} with Gemfile pointing to your Rails checkout"

        class_option :edge,               type: :boolean, default: false,
                                          desc: "Setup the #{name} with Gemfile pointing to Rails repository"

        class_option :skip_test_unit,     type: :boolean, aliases: '-T', default: false,
                                          desc: 'Skip Test::Unit files'

        class_option :rc,                 type: :string, default: false,
                                          desc: "Path to file containing extra configuration options for rails command"

        class_option :no_rc,              type: :boolean, default: false,
                                          desc: 'Skip loading of extra configuration options from .railsrc file'

        class_option :help,               type: :boolean, aliases: '-h', group: :rails,
                                          desc: 'Show this help message and quit'
      end

      def initialize(*args)
        @original_wd = Dir.pwd
        super
        convert_database_option_for_jruby
      end

    protected

      def builder
        @builder ||= begin
          builder_class = get_builder_class
          builder_class.send(:include, ActionMethods)
          builder_class.new(self)
        end
      end

      def build(meth, *args)
        builder.send(meth, *args) if builder.respond_to?(meth)
      end

      def create_root
        valid_const?

        empty_directory '.'
        FileUtils.cd(destination_root) unless options[:pretend]
      end

      def apply_rails_template
        apply rails_template if rails_template
      rescue Thor::Error, LoadError, Errno::ENOENT => e
        raise Error, "The template [#{rails_template}] could not be loaded. Error: #{e}"
      end

      def set_default_accessors!
        self.destination_root = File.expand_path(app_path, destination_root)
        self.rails_template = case options[:template]
          when /^https?:\/\//
            options[:template]
          when String
            File.expand_path(options[:template], Dir.pwd)
          else
            options[:template]
        end
      end

      def database_gemfile_entry
        return [] if options[:skip_active_record]
         GemfileEntry.version gem_for_database, nil,
                             "Use #{options[:database]} as the database for Active Record"
      end

      def include_all_railties?
        !options[:skip_active_record] && !options[:skip_action_view] && !options[:skip_test_unit] && !options[:skip_sprockets]
      end

      def comment_if(value)
        options[value] ? '# ' : ''
      end

      class GemfileEntry < Struct.new(:name, :comment, :version, :options, :commented_out)
        def initialize(name, comment, version, options = {}, commented_out = false)
          super
        end

        def self.github(name, github, comment = nil)
          new(name, comment, nil, github: github)
        end

        def self.version(name, version, comment = nil)
          new(name, comment, version)
        end

        def self.path(name, path, comment = nil)
          new(name, comment, nil, path: path)
        end

        def github; options[:github]; end
        def path; options[:path]; end
        def platforms; options[:platforms]; end

        def padding(max_width)
          ' ' * (max_width - name.length + 2)
        end
      end

      def rails_gemfile_entry
        if options.dev?
          [GemfileEntry.path('rails', Rails::Generators::RAILS_DEV_PATH),
           GemfileEntry.github('arel', 'rails/arel')]
        elsif options.edge?
          [GemfileEntry.path('rails', 'rails/rails'),
           GemfileEntry.path('arel', 'rails/arel')]
        else
          [GemfileEntry.version('rails',
                            Rails::VERSION::STRING,
                            "Bundle edge Rails instead: gem 'rails', github: 'rails/rails'")]
        end
      end

      def gem_for_database
        # %w( mysql oracle postgresql sqlite3 frontbase ibm_db sqlserver jdbcmysql jdbcsqlite3 jdbcpostgresql )
        case options[:database]
        when "oracle"         then "ruby-oci8"
        when "postgresql"     then "pg"
        when "frontbase"      then "ruby-frontbase"
        when "mysql"          then "mysql2"
        when "sqlserver"      then "activerecord-sqlserver-adapter"
        when "jdbcmysql"      then "activerecord-jdbcmysql-adapter"
        when "jdbcsqlite3"    then "activerecord-jdbcsqlite3-adapter"
        when "jdbcpostgresql" then "activerecord-jdbcpostgresql-adapter"
        when "jdbc"           then "activerecord-jdbc-adapter"
        else options[:database]
        end
      end

      def convert_database_option_for_jruby
        if defined?(JRUBY_VERSION)
          case options[:database]
          when "oracle"     then options[:database].replace "jdbc"
          when "postgresql" then options[:database].replace "jdbcpostgresql"
          when "mysql"      then options[:database].replace "jdbcmysql"
          when "sqlite3"    then options[:database].replace "jdbcsqlite3"
          end
        end
      end

      def assets_gemfile_entry
        return [] if options[:skip_sprockets]

        gems = []
        gemfile = if options.dev? || options.edge?
          gems << GemfileEntry.github('sprockets-rails', 'rails/sprockets-rails',
                                    'Use edge version of sprockets-rails')
          gems << GemfileEntry.github('sass-rails', 'rails/sass-rails',
                                    'Use SCSS for stylesheets')
        else
          gems << GemfileEntry.version('sass-rails',
                                     '~> 4.0.0.rc1',
                                     'Use SCSS for stylesheets')
        end

        gems << GemfileEntry.version('uglifier',
                                   '>= 1.3.0',
                                   'Use Uglifier as compressor for JavaScript assets')

        if options[:skip_javascript]
          gems << coffee_gemfile_entry
          gems << javascript_runtime_gemfile_entry
        end

        gems
      end

      def jbuilder_gemfile_entry
        comment = 'Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder'
        GemfileEntry.version('jbuilder', '~> 1.2', comment)
      end

      def webconsole_gemfile_entry
        comment = 'Run `rails console` in the browser. Read more: https://github.com/rails/web-console'
        GemfileEntry.new('web-console', comment, nil, group: :development)
      end

      def sdoc_gemfile_entry
        comment = 'bundle exec rake doc:rails generates the API under doc/api.'
        GemfileEntry.new('web-console', comment, nil, { :group => :doc, :require => false })
      end

      def coffee_gemfile_entry
        comment = 'Use CoffeeScript for .js.coffee assets and views'
        if options.dev? || options.edge?
          GemfileEntry.github 'coffee-rails', 'rails/coffee-rails', comment
        else
          GemfileEntry.version 'coffee-rails', '~> 4.0.0', comment
        end
      end

      def javascript_gemfile_entry
        if options[:skip_javascript]
          []
        else
          gems = [coffee_gemfile_entry, javascript_runtime_gemfile_entry]
          gems << GemfileEntry.version("#{options[:javascript]}-rails", nil,
                                 "Use #{options[:javascript]} as the JavaScript library")

          gems << GemfileEntry.version("turbolinks", nil,
            "Turbolinks makes following links in your web application faster. Read more: https://github.com/rails/turbolinks")
          gems
        end
      end

      def javascript_runtime_gemfile_entry
        comment = 'See https://github.com/sstephenson/execjs#readme for more supported runtimes'
        runtime = if defined?(JRUBY_VERSION)
          GemfileEntry.version 'therubyrhino', comment, nil
        else
          GemfileEntry.new 'therubyracer', comment, nil, { :platforms => :ruby }, true
        end
      end

      def bundle_command(command)
        say_status :run, "bundle #{command}"

        # We are going to shell out rather than invoking Bundler::CLI.new(command)
        # because `rails new` loads the Thor gem and on the other hand bundler uses
        # its own vendored Thor, which could be a different version. Running both
        # things in the same process is a recipe for a night with paracetamol.
        #
        # We use backticks and #print here instead of vanilla #system because it
        # is easier to silence stdout in the existing test suite this way. The
        # end-user gets the bundler commands called anyway, so no big deal.
        #
        # We unset temporary bundler variables to load proper bundler and Gemfile.
        #
        # Thanks to James Tucker for the Gem tricks involved in this call.
        _bundle_command = Gem.bin_path('bundler', 'bundle')

        require 'bundler'
        Bundler.with_clean_env do
          print `"#{Gem.ruby}" "#{_bundle_command}" #{command}`
        end
      end

      def run_bundle
        bundle_command('install') unless options[:skip_gemfile] || options[:skip_bundle] || options[:pretend]
      end

      def empty_directory_with_keep_file(destination, config = {})
        empty_directory(destination, config)
        keep_file(destination)
      end

      def keep_file(destination)
        create_file("#{destination}/.keep") unless options[:skip_keeps]
      end
    end
  end
end
