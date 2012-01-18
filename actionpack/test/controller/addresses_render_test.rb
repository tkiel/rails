require 'abstract_unit'
require 'active_support/logger'
require 'controller/fake_controllers'

class Address
  class << self
    def count(conditions = nil, join = nil)
      nil
    end

    def find_all(arg1, arg2, arg3, arg4)
      []
    end

    def find(*args)
      []
    end
  end
end

class AddressesTest < ActionController::TestCase
  tests AddressesController

  def setup
    super
    # enable a logger so that (e.g.) the benchmarking stuff runs, so we can get
    # a more accurate simulation of what happens in "real life".
    @controller.logger = ActiveSupport::Logger.new(nil)

    @request.host = "www.nextangle.com"
  end

  def test_list
    get :list
    assert_equal "We only need to get this far!", @response.body.chomp
  end
end
