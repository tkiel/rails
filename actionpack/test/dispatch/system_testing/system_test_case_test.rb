require "abstract_unit"

class DrivenByRackTestTest < ActionDispatch::SystemTestCase
  driven_by :rack_test

  test "uses rack_test" do
    assert_equal :rack_test, Capybara.current_driver
  end
end

class DrivenBySeleniumWithChromeTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :chrome

  test "uses selenium" do
    assert_equal :chrome, Capybara.current_driver
  end
end
