require 'active_support/core_ext/file/path'
require 'rack/chunked'

module ActionController #:nodoc:
  # Allows views to be streamed back to the client as they are rendered.
  #
  # The default way Rails renders views is by first rendering the template
  # and then the layout. The response is sent to the client after the whole
  # template is rendered, all queries are made, and the layout is processed.
  #
  # Streaming inverts the rendering flow by rendering the layout first and
  # streaming each part of the layout as they are processed. This allows the
  # header of the HTML (which is usually in the layout) to be streamed back
  # to client very quickly, allowing JavaScripts and stylesheets to be loaded
  # earlier than usual.
  #
  # This approach was introduced in Rails 3.1 and is still improving. Several
  # Rack middlewares may not work and you need to be careful when streaming.
  # Those points are going to be addressed soon.
  #
  # In order to use streaming, you will need to use a Ruby version that
  # supports fibers (fibers are supported since version 1.9.2 of the main
  # Ruby implementation).
  #
  # == Examples
  #
  # Streaming can be added to a controller easily, all you need to do is
  # call +stream+ in the controller class:
  #
  #   class PostsController
  #     stream
  #   end
  #
  # The +stream+ method accepts the same options as +before_filter+ and friends:
  #
  #   class PostsController
  #     stream :only => :index
  #   end
  #
  # You can also selectively turn on streaming for specific actions:
  #
  #   class PostsController
  #     def index
  #       @posts = Post.scoped
  #       render :stream => true
  #     end
  #   end
  #
  # == When to use streaming
  #
  # Streaming may be considered to be overkill for lightweight actions like
  # +new+ or +edit+. The real benefit of streaming is on expensive actions
  # that, for example, do a lot of queries on the database.
  #
  # In such actions, you want to delay queries execution as much as you can.
  # For example, imagine the following +dashboard+ action:
  #
  #   def dashboard
  #     @posts = Post.all
  #     @pages = Page.all
  #     @articles = Article.all
  #   end
  #
  # Most of the queries here are happening in the controller. In order to benefit
  # from streaming you would want to rewrite it as:
  #
  #   def dashboard
  #     # Allow lazy execution of the queries
  #     @posts = Post.scoped
  #     @pages = Page.scoped
  #     @articles = Article.scoped
  #     render :stream => true
  #   end
  #
  # == Communication between layout and template
  #
  # When streaming, rendering happens top-down instead of inside-out.
  # Rails starts with the layout, and the template is rendered later,
  # when its +yield+ is reached.
  #
  # This means that, if your application currently relies on instance
  # variables set in the template to be used in the layout, they won't
  # work once you move to streaming. The proper way to communicate
  # between layout and template, regardless of whether you use streaming
  # or not, is by using +content_for+, +provide+ and +yield+.
  #
  # Take a simple example where the layout expects the template to tell
  # which title to use:
  #
  #   <html>
  #     <head><title><%= yield :title %></title></head>
  #     <body><%= yield %></body>
  #   </html>
  #
  # You would use +content_for+ in your template to specify the title:
  #
  #   <%= content_for :title, "Main" %>
  #   Hello
  #
  # And the final result would be:
  #
  #   <html>
  #     <head><title>Main</title></head>
  #     <body>Hello</body>
  #   </html>
  #
  # However, if +content_for+ is called several times, the final result
  # would have all calls concatenated. For instance, if we have the following
  # template:
  #
  #   <%= content_for :title, "Main" %>
  #   Hello
  #   <%= content_for :title, " page" %>
  #
  # The final result would be:
  #
  #   <html>
  #     <head><title>Main page</title></head>
  #     <body>Hello</body>
  #   </html>
  #
  # This means that, if you have <code>yield :title</code> in your layout
  # and you want to use streaming, you would have to render the whole template
  # (and eventually trigger all queries) before streaming the title and all
  # assets, which kills the purpose of streaming. For this reason Rails 3.1
  # introduces a new helper called +provide+ that does the same as +content_for+
  # but tells the layout to stop searching for other entries and continue rendering.
  #
  # For instance, the template above using +provide+ would be:
  #
  #   <%= provide :title, "Main" %>
  #   Hello
  #   <%= content_for :title, " page" %>
  #
  # Giving:
  #
  #   <html>
  #     <head><title>Main</title></head>
  #     <body>Hello</body>
  #   </html>
  #
  # That said, when streaming, you need to properly check your templates
  # and choose when to use +provide+ and +content_for+.
  #
  # == Headers, cookies, session and flash
  #
  # When streaming, the HTTP headers are sent to the client right before
  # it renders the first line. This means that, modifying headers, cookies,
  # session or flash after the template starts rendering will not propagate
  # to the client.
  #
  # If you try to modify cookies, session or flash, an +ActionDispatch::ClosedError+
  # will be raised, showing those objects are closed for modification.
  #
  # == Middlewares
  #
  # Middlewares that need to manipulate the body won't work with streaming.
  # You should disable those middlewares whenever streaming in development
  # or production. For instance, +Rack::Bug+ won't work when streaming as it
  # needs to inject contents in the HTML body.
  #
  # Also +Rack::Cache+ won't work with streaming as it does not support
  # streaming bodies yet. Whenever streaming Cache-Control is automatically
  # set to "no-cache".
  #
  # == Errors
  #
  # When it comes to streaming, exceptions get a bit more complicated. This
  # happens because part of the template was already rendered and streamed to
  # the client, making it impossible to render a whole exception page.
  #
  # Currently, when an exception happens in development or production, Rails
  # will automatically stream to the client:
  #
  #   "><script type="text/javascript">window.location = "/500.html"</script></html>
  #
  # The first two characters (">) are required in case the exception happens
  # while rendering attributes for a given tag. You can check the real cause
  # for the exception in your logger.
  #
  # == Web server support
  #
  # Not all web servers support streaming out-of-the-box. You need to check
  # the instructions for each of them.
  #
  # ==== Unicorn
  #
  # Unicorn supports streaming but it needs to be configured. For this, you
  # need to create a config file as follow:
  #
  #   # unicorn.config.rb
  #   listen 3000, :tcp_nopush => false
  #
  # And use it on initialization:
  #
  #   unicorn_rails --config-file unicorn.config.rb
  #
  # You may also want to configure other parameters like <tt>:tcp_nodelay</tt>.
  # Please check its documentation for more information: http://unicorn.bogomips.org/Unicorn/Configurator.html#method-i-listen
  #
  # If you are using Unicorn with Nginx, you may need to tweak Nginx.
  # Streaming should work out of the box on Rainbows.
  #
  # ==== Passenger
  #
  # To be described.
  # 
  module Streaming
    extend ActiveSupport::Concern

    include AbstractController::Rendering
    attr_internal :stream

    module ClassMethods
      # Render streaming templates. It accepts :only, :except, :if and :unless as options
      # to specify when to stream, as in ActionController filters.
      def stream(options={})
        if defined?(Fiber)
          before_filter :_stream_filter, options
        else
          raise "You cannot use streaming if Fiber is not available."
        end
      end
    end

    protected

    # Mark following render calls as streaming.
    def _stream_filter #:nodoc:
      self.stream = true
    end

    # Consider the stream option when normalazing options.
    def _normalize_options(options) #:nodoc:
      super
      options[:stream] = self.stream unless options.key?(:stream)
    end

    # Set proper cache control and transfer encoding when streaming
    def _process_options(options) #:nodoc:
      super
      if options[:stream]
        if env["HTTP_VERSION"] == "HTTP/1.0"
          options.delete(:stream)
        else
          headers["Cache-Control"] ||= "no-cache"
          headers["Transfer-Encoding"] = "chunked"
          headers.delete("Content-Length")
        end
      end
    end

    # Call render_to_body if we are streaming instead of usual +render+.
    def _render_template(options) #:nodoc:
      if options.delete(:stream)
        Rack::Chunked::Body.new view_renderer.render_body(view_context, options)
      else
        super
      end
    end
  end
end
      