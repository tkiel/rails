module Rails
  module Rack
    # Enables easy tagging of any logging activity that occurs within the Rails request cycle. The tags are configured via the
    # config.log_tags setting. The tags can either be strings, procs taking a request argument, or the symbols :uuid or :subdomain.
    # The latter two are then automatically expanded to request.uuid and request.subdaomins.first -- the two most common tags
    # desired in production logs.
    class TaggedLogging
      def initialize(app, tags = nil)
        @app, @tags = app, tags
      end

      def call(env)
        if @tags
          Rails.logger.tagged(compute_tags(env)) { @app.call(env) }
        else
          @app.call(env)
        end
      end
      
      private
        def compute_tags(env)
          request = ActionDispatch::Request.new(env)

          @tags.collect do |tag|
            case tag
            when Proc
              tag.call(request)
            when :uuid
              request.uuid
            when :subdomain
              request.subdomains.first
            else
              tag
            end
          end
        end
    end
  end
end
