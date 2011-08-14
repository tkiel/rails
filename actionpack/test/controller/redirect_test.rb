require 'abstract_unit'

class WorkshopsController < ActionController::Base
end

class RedirectController < ActionController::Base
  # empty method not used anywhere to ensure methods like
  # `status` and `location` aren't called on `redirect_to` calls
  def status; render :text => 'called status'; end
  def location; render :text => 'called location'; end

  def simple_redirect
    redirect_to :action => "hello_world"
  end

  def redirect_with_status
    redirect_to({:action => "hello_world", :status => 301})
  end

  def redirect_with_status_hash
    redirect_to({:action => "hello_world"}, {:status => 301})
  end

  def redirect_with_protocol
    redirect_to :action => "hello_world", :protocol => "https"
  end

  def url_redirect_with_status
    redirect_to("http://www.example.com", :status => :moved_permanently)
  end

  def url_redirect_with_status_hash
    redirect_to("http://www.example.com", {:status => 301})
  end

  def relative_url_redirect_with_status
    redirect_to("/things/stuff", :status => :found)
  end

  def relative_url_redirect_with_status_hash
    redirect_to("/things/stuff", {:status => 301})
  end

  def redirect_to_back_with_status
    redirect_to :back, :status => 307
  end

  def host_redirect
    redirect_to :action => "other_host", :only_path => false, :host => 'other.test.host'
  end

  def module_redirect
    redirect_to :controller => 'module_test/module_redirect', :action => "hello_world"
  end

  def redirect_with_assigns
    @hello = "world"
    redirect_to :action => "hello_world"
  end

  def redirect_to_url
    redirect_to "http://www.rubyonrails.org/"
  end

  def redirect_to_url_with_unescaped_query_string
    redirect_to "http://dev.rubyonrails.org/query?status=new"
  end

  def redirect_to_url_with_complex_scheme
    redirect_to "x-test+scheme.complex:redirect"
  end

  def redirect_to_back
    redirect_to :back
  end

  def redirect_to_existing_record
    redirect_to Workshop.new(5)
  end

  def redirect_to_new_record
    redirect_to Workshop.new(nil)
  end

  def redirect_to_nil
    redirect_to nil
  end

  def redirect_to_with_block
    redirect_to proc { "http://www.rubyonrails.org/" }
  end

  def redirect_to_with_block_and_assigns
    @url = "http://www.rubyonrails.org/"
    redirect_to proc { @url }
  end

  def redirect_to_with_block_and_options
    redirect_to proc { {:action => "hello_world"} }
  end

  def rescue_errors(e) raise e end

  def rescue_action(e) raise end

  protected
    def dashbord_url(id, message)
      url_for :action => "dashboard", :params => { "id" => id, "message" => message }
    end
end

class RedirectTest < ActionController::TestCase
  tests RedirectController

  def test_simple_redirect
    get :simple_redirect
    assert_response :redirect
    assert_equal "http://test.host/redirect/hello_world", redirect_to_url
  end

  def test_redirect_with_no_status
    get :simple_redirect
    assert_response 302
    assert_equal "http://test.host/redirect/hello_world", redirect_to_url
  end

  def test_redirect_with_status
    get :redirect_with_status
    assert_response 301
    assert_equal "http://test.host/redirect/hello_world", redirect_to_url
  end

  def test_redirect_with_status_hash
    get :redirect_with_status_hash
    assert_response 301
    assert_equal "http://test.host/redirect/hello_world", redirect_to_url
  end

  def test_redirect_with_protocol
    get :redirect_with_protocol
    assert_response 302
    assert_equal "https://test.host/redirect/hello_world", redirect_to_url
  end

  def test_url_redirect_with_status
    get :url_redirect_with_status
    assert_response 301
    assert_equal "http://www.example.com", redirect_to_url
  end

  def test_url_redirect_with_status_hash
    get :url_redirect_with_status_hash
    assert_response 301
    assert_equal "http://www.example.com", redirect_to_url
  end


  def test_relative_url_redirect_with_status
    get :relative_url_redirect_with_status
    assert_response 302
    assert_equal "http://test.host/things/stuff", redirect_to_url
  end

  def test_relative_url_redirect_with_status_hash
    get :relative_url_redirect_with_status_hash
    assert_response 301
    assert_equal "http://test.host/things/stuff", redirect_to_url
  end

  def test_redirect_to_back_with_status
    @request.env["HTTP_REFERER"] = "http://www.example.com/coming/from"
    get :redirect_to_back_with_status
    assert_response 307
    assert_equal "http://www.example.com/coming/from", redirect_to_url
  end

  def test_simple_redirect_using_options
    get :host_redirect
    assert_response :redirect
    assert_redirected_to :action => "other_host", :only_path => false, :host => 'other.test.host'
  end

  def test_module_redirect
    get :module_redirect
    assert_response :redirect
    assert_redirected_to "http://test.host/module_test/module_redirect/hello_world"
  end

  def test_module_redirect_using_options
    get :module_redirect
    assert_response :redirect
    assert_redirected_to :controller => 'module_test/module_redirect', :action => 'hello_world'
  end

  def test_redirect_with_assigns
    get :redirect_with_assigns
    assert_response :redirect
    assert_equal "world", assigns["hello"]
  end

  def test_redirect_to_url
    get :redirect_to_url
    assert_response :redirect
    assert_redirected_to "http://www.rubyonrails.org/"
  end

  def test_redirect_to_url_with_unescaped_query_string
    get :redirect_to_url_with_unescaped_query_string
    assert_response :redirect
    assert_redirected_to "http://dev.rubyonrails.org/query?status=new"
  end

  def test_redirect_to_url_with_complex_scheme
    get :redirect_to_url_with_complex_scheme
    assert_response :redirect
    assert_equal "x-test+scheme.complex:redirect", redirect_to_url
  end

  def test_redirect_to_back
    @request.env["HTTP_REFERER"] = "http://www.example.com/coming/from"
    get :redirect_to_back
    assert_response :redirect
    assert_equal "http://www.example.com/coming/from", redirect_to_url
  end

  def test_redirect_to_back_with_no_referer
    assert_raise(ActionController::RedirectBackError) {
      @request.env["HTTP_REFERER"] = nil
      get :redirect_to_back
    }
  end

  def test_redirect_to_record
    with_routing do |set|
      set.draw do
        resources :workshops
        match ':controller/:action'
      end

      get :redirect_to_existing_record
      assert_equal "http://test.host/workshops/5", redirect_to_url
      assert_redirected_to Workshop.new(5)

      get :redirect_to_new_record
      assert_equal "http://test.host/workshops", redirect_to_url
      assert_redirected_to Workshop.new(nil)
    end
  end

  def test_redirect_to_nil
    assert_raise(ActionController::ActionControllerError) do
      get :redirect_to_nil
    end
  end

  def test_redirect_to_with_block
    get :redirect_to_with_block
    assert_response :redirect
    assert_redirected_to "http://www.rubyonrails.org/"
  end

  def test_redirect_to_with_block_and_assigns
    get :redirect_to_with_block_and_assigns
    assert_response :redirect
    assert_redirected_to "http://www.rubyonrails.org/"
  end

  def test_redirect_to_with_block_and_accepted_options
    with_routing do |set|
      set.draw do
        match ':controller/:action'
      end

      get :redirect_to_with_block_and_options

      assert_response :redirect
      assert_redirected_to "http://test.host/redirect/hello_world"
    end
  end
end

module ModuleTest
  class ModuleRedirectController < ::RedirectController
    def module_redirect
      redirect_to :controller => '/redirect', :action => "hello_world"
    end
  end

  class ModuleRedirectTest < ActionController::TestCase
    tests ModuleRedirectController

    def test_simple_redirect
      get :simple_redirect
      assert_response :redirect
      assert_equal "http://test.host/module_test/module_redirect/hello_world", redirect_to_url
    end

    def test_simple_redirect_using_options
      get :host_redirect
      assert_response :redirect
      assert_redirected_to :action => "other_host", :only_path => false, :host => 'other.test.host'
    end

    def test_module_redirect
      get :module_redirect
      assert_response :redirect
      assert_equal "http://test.host/redirect/hello_world", redirect_to_url
    end

    def test_module_redirect_using_options
      get :module_redirect
      assert_response :redirect
      assert_redirected_to :controller => '/redirect', :action => "hello_world"
    end
  end
end
