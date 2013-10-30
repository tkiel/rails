require 'active_support/test_case'
require 'active_support/testing/autorun'
require 'rails/generators/rails/app/app_generator'
require 'tempfile'

module Rails
  module Generators
    class ARGVScrubberTest < ActiveSupport::TestCase
      def test_version
        ['-v', '--version'].each do |str|
          scrubber = ARGVScrubber.new [str]
          output    = nil
          exit_code = nil
          scrubber.extend(Module.new {
            define_method(:puts) { |str| output = str }
            define_method(:exit) { |code| exit_code = code }
          })
          scrubber.prepare!
          assert_equal "Rails #{Rails::VERSION::STRING}", output
          assert_equal 0, exit_code
        end
      end

      def test_prepare_returns_args
        scrubber = ARGVScrubber.new ['hi mom']
        args = scrubber.prepare!
        assert_equal '--help', args.first
      end

      def test_no_mutations
        scrubber = ARGVScrubber.new ['hi mom'].freeze
        args = scrubber.prepare!
        assert_equal '--help', args.first
      end

      def test_new_command_no_rc
        scrubber = Class.new(ARGVScrubber) {
          def self.default_rc_file
            File.join(Dir.tmpdir, 'whatever')
          end
        }.new ['new']
        args = scrubber.prepare!
        assert_equal [], args
      end

      def test_new_homedir_rc
        file = Tempfile.new 'myrcfile'
        file.puts '--hello-world'
        file.flush

        message = nil
        scrubber = Class.new(ARGVScrubber) {
          define_singleton_method(:default_rc_file) do
            file.path
          end
          define_method(:puts) { |msg| message = msg }
        }.new ['new']
        args = scrubber.prepare!
        assert_equal [nil, '--hello-world'], args
        assert_match 'hello-world', message
        assert_match file.path, message
      ensure
        file.close
        file.unlink
      end

      def test_no_rc
        scrubber = ARGVScrubber.new ['new', '--no-rc']
        args = scrubber.prepare!
        assert_equal [], args
      end
    end
  end
end
