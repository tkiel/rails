require "cases/helper"

class TestAdapterWithInvalidConnection < ActiveRecord::TestCase
  self.use_transactional_fixtures = false

  class Bird < ActiveRecord::Base
    # Can't just use current adapter; sqlite3 will create a database
    # file on the fly.
    establish_connection adapter: 'mysql', database: 'i_do_not_exist'
  end

  test "inspect on Model class does not raise" do
    assert_equal "#{Bird.name}(no database connection)", Bird.inspect
  end
end
