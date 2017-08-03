require "pathname"
require_relative "version"

module Rails
  module AppLoader # :nodoc:
    extend self

    RUBY = Gem.ruby
    EXECUTABLES = ["bin/rails", "script/rails"]
    BUNDLER_WARNING = <<EOS
Beginning in Rails 4, Rails ships with a `rails` binstub at ./bin/rails that
should be used instead of the Bundler-generated `rails` binstub.

If you are seeing this message, your binstub at ./bin/rails was generated by
Bundler instead of Rails.

You might need to regenerate your `rails` binstub locally and add it to source
control:

 rails app:update:bin           # Bear in mind this generates other binstubs
                                # too that you may or may not want (like yarn)

If you already have Rails binstubs in source control, you might be
inadverently overwriting them during deployment by using bundle install
with the --binstubs option.

If your application was created prior to Rails 4, here's how to upgrade:

  bundle config --delete bin    # Turn off Bundler's stub generator
  rails app:update:bin          # Use the new Rails executables
  git add bin                   # Add bin/ to source control

You may need to remove bin/ from your .gitignore as well.

When you install a gem whose executable you want to use in your app,
generate it and add it to source control:

  bundle binstubs some-gem-name
  git add bin/new-executable

EOS

    def exec_app
      original_cwd = Dir.pwd

      loop do
        if exe = find_executable
          contents = File.read(exe)

          if contents =~ /(APP|ENGINE)_PATH/
            exec RUBY, exe, *ARGV
            break # non reachable, hack to be able to stub exec in the test suite
          elsif exe.end_with?("bin/rails") && contents.include?("This file was generated by Bundler")
            $stderr.puts(BUNDLER_WARNING)
            Object.const_set(:APP_PATH, File.expand_path("config/application", Dir.pwd))
            require File.expand_path("../boot", APP_PATH)
            require_relative "commands"
            break
          end
        end

        # If we exhaust the search there is no executable, this could be a
        # call to generate a new application, so restore the original cwd.
        Dir.chdir(original_cwd) && return if Pathname.new(Dir.pwd).root?

        # Otherwise keep moving upwards in search of an executable.
        Dir.chdir("..")
      end
    end

    def find_executable
      EXECUTABLES.find { |exe| File.file?(exe) }
    end
  end
end
