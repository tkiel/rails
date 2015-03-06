module ActionController
  # Includes +url_for+ into the host class. The class has to provide a +RouteSet+ by implementing
  # the <tt>_routes</tt> method. Otherwise, an exception will be raised.
  #
  # In addition to <tt>AbstractController::UrlFor</tt>, this module accesses the HTTP layer to define
  # url options like the +host+. In order to do so, this module requires the host class
  # to implement +env+ which needs to be Rack-compatible and +request+
  # which is either instance of +ActionDispatch::Request+ or an object
  # that responds to <tt>host</tt>, <tt>optional_port</tt>, <tt>protocol</tt> and
  # <tt>symbolized_path_parameter</tt> methods.
  #
  #   class RootUrl
  #     include ActionController::UrlFor
  #     include Rails.application.routes.url_helpers
  #
  #     delegate :env, :request, to: :controller
  #
  #     def initialize(controller)
  #       @controller = controller
  #       @url        = root_path # named route from the application.
  #     end
  #   end
  module UrlFor
    extend ActiveSupport::Concern

    include AbstractController::UrlFor

    def url_options
      @_url_options ||= {
        :host => request.host,
        :port => request.optional_port,
        :protocol => request.protocol,
        :_recall => request.path_parameters
      }.merge!(super).freeze

      if (same_origin = _routes.equal?(request.routes)) ||
         (script_name = request.engine_script_name(_routes)) ||
         (original_script_name = request.original_script_name)

        options = @_url_options.dup
        if original_script_name
          options[:original_script_name] = original_script_name
        else
          options[:script_name] = same_origin ? request.script_name.dup : script_name
        end
        options.freeze
      else
        @_url_options
      end
    end
  end
end
