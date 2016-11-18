begin
  require "rack/handler/puma"
rescue LoadError
  false
end

module ActionSystemTest
  module DriverAdapters
    module WebServer # :nodoc:
      def register_server
        Capybara.register_server @server do |app, port, host|
          case @server
          when :puma
            register_puma(app, port)
          when :webrick
            register_webrick(app, port)
          else
            register_default(app, port)
          end
        end
      end

      private
        def register_default(app, port)
          Capybara.run_default_server(app, port)
        end

        def register_puma(app, port)
          Rack::Handler::Puma.run(app, Port: port, Threads: "0:4")
        end

        def register_webrick(app, port)
          Rack::Handler::WEBrick.run(app, Port: port, AccessLog: [], Logger: WEBrick::Log::new(nil, 0))
        end

        def set_server
          Capybara.server = @server
        end

        def set_port
          Capybara.server_port = @port
        end
    end
  end
end
