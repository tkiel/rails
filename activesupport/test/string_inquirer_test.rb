require "abstract_unit"

class StringInquirerTest < ActiveSupport::TestCase
  def setup
    @string_inquirer = ActiveSupport::StringInquirer.new("production")
  end

  def test_match
    assert @string_inquirer.production?
  end

  def test_miss
    assert_not @string_inquirer.development?
  end

  def test_missing_question_mark
    assert_raise(NoMethodError) { @string_inquirer.production }
  end

  def test_respond_to
    assert_respond_to @string_inquirer, :development?
  end

  def test_respond_to_fallback_to_string_respond_to
    String.class_eval do
      def respond_to_missing?(name, include_private = false)
        (name == :bar) || super
      end
    end
    str = ActiveSupport::StringInquirer.new("hello")

    assert_respond_to str, :are_you_ready?
    assert_respond_to str, :bar
    assert_not_respond_to str, :nope

  ensure
    String.send :undef_method, :respond_to_missing?
  end
end
