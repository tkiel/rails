require "ostruct"
require "optparse"
require "rake/file_list"
require "method_source"

module Rails
  class TestRunner
    class Options
      def self.parse(args)
        options = { backtrace: false, name: nil }

        opt_parser = ::OptionParser.new do |opts|
          opts.banner = "Usage: bin/rails test [options]"

          opts.separator ""
          opts.separator "Filter options:"

          opts.on("-n", "--name [NAME]",
                  "Only run tests matching NAME") do |name|
            options[:name] = name
          end

          opts.separator ""
          opts.separator "Output options:"

          opts.on("-b", "--backtrace",
                  "show the complte backtrace") do
            options[:backtrace] = true
          end

          opts.separator ""
          opts.separator "Common options:"

          opts.on_tail("-h", "--help", "Show this message") do
            puts opts
            exit
          end
        end

        opt_parser.order!(args)

        if arg = args.shift
          if NAMED_PATTERNS.key?(arg)
            options[:pattern] = arg
          else
            options[:filename], options[:line] = arg.split(':')
            options[:filename] = File.expand_path options[:filename]
            options[:line] &&= options[:line].to_i
          end
        end
        options
      end
    end

    def initialize(options = {})
      @options = options
    end

    def run
      enable_backtrace if @options[:backtrace]

      run_tests
    end

    def find_method
      return @options[:name] if @options[:name]
      return unless @options[:line]
      method = test_methods.find do |location, test_method, start_line, end_line|
        location == @options[:filename] &&
          (start_line..end_line).include?(@options[:line].to_i)
      end
      method[1] if method
    end

    private
    def run_tests
      test_files.to_a.each do |file|
        require File.expand_path file
      end
    end

    NAMED_PATTERNS = {
      "models" => "test/models/**/*_test.rb"
    }
    def test_files
      return [@options[:filename]] if @options[:filename]
      if @options[:pattern]
        pattern = NAMED_PATTERNS[@options[:pattern]]
      else
        pattern = "test/**/*_test.rb"
      end
      Rake::FileList[pattern]
    end

    def enable_backtrace
      ENV["BACKTRACE"] = "1"
    end

    def test_methods
      methods_map = []
      suites = Minitest::Runnable.runnables.shuffle
      suites.each do |suite_class|
        suite_class.runnable_methods.each do |test_method|
          method = suite_class.instance_method(test_method)
          location = method.source_location
          start_line = location.last
          end_line = method.source.split("\n").size + start_line - 1
          methods_map << [location.first, test_method, start_line, end_line]
        end
      end
      methods_map
    end
  end
end
