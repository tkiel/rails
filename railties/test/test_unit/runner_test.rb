require 'abstract_unit'
require 'rails/test_unit/runner'

class TestUnitTestRunnerTest < ActiveSupport::TestCase
  setup do
    @options = Rails::TestRunner::Options
  end

  test "shows the filtered backtrace by default" do
    options = @options.parse([])
    assert_not options[:backtrace]
  end

  test "has --backtrace (-b) option to show the full backtrace" do
    options = @options.parse(["-b"])
    assert options[:backtrace]

    options = @options.parse(["--backtrace"])
    assert options[:backtrace]
  end

  test "tests run in the test environment by default" do
    options = @options.parse([])
    assert_equal "test", options[:environment]
  end

  test "can run in a specific environment" do
    options = @options.parse(["-e development"])
    assert_equal "development", options[:environment]
  end

  test "parse the filename and line" do
    options = @options.parse(["foobar.rb:20"])
    assert_equal File.expand_path("foobar.rb"), options[:filename]
    assert_equal 20, options[:line]

    options = @options.parse(["foobar.rb:"])
    assert_equal File.expand_path("foobar.rb"), options[:filename]
    assert_nil options[:line]

    options = @options.parse(["foobar.rb"])
    assert_equal File.expand_path("foobar.rb"), options[:filename]
    assert_nil options[:line]
  end

  test "find_method on same file" do
    options = @options.parse(["#{__FILE__}:#{__LINE__}"])
    runner = Rails::TestRunner.new(options)
    assert_equal "test_find_method_on_same_file", runner.find_method
  end

  test "find_method on a different file" do
    options = @options.parse(["foobar.rb:#{__LINE__}"])
    runner = Rails::TestRunner.new(options)
    assert_nil runner.find_method
  end

  test "run all tests in a directory" do
    options = @options.parse([__dir__])

    assert_equal "#{__dir__}/**/*_test.rb", options[:pattern]
    assert_nil options[:filename]
    assert_nil options[:line]
  end

  test "run multiple files" do
    skip "needs implementation"
  end
end
