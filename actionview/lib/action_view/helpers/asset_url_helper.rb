require "zlib"
require "active_support/core_ext/regexp"

module ActionView
  # = Action View Asset URL Helpers
  module Helpers
    # This module provides methods for generating asset paths and
    # urls.
    #
    #   image_path("rails.png")
    #   # => "/assets/rails.png"
    #
    #   image_url("rails.png")
    #   # => "http://www.example.com/assets/rails.png"
    #
    # === Using asset hosts
    #
    # By default, Rails links to these assets on the current host in the public
    # folder, but you can direct Rails to link to assets from a dedicated asset
    # server by setting <tt>ActionController::Base.asset_host</tt> in the application
    # configuration, typically in <tt>config/environments/production.rb</tt>.
    # For example, you'd define <tt>assets.example.com</tt> to be your asset
    # host this way, inside the <tt>configure</tt> block of your environment-specific
    # configuration files or <tt>config/application.rb</tt>:
    #
    #   config.action_controller.asset_host = "assets.example.com"
    #
    # Helpers take that into account:
    #
    #   image_tag("rails.png")
    #   # => <img alt="Rails" src="http://assets.example.com/assets/rails.png" />
    #   stylesheet_link_tag("application")
    #   # => <link href="http://assets.example.com/assets/application.css" media="screen" rel="stylesheet" />
    #
    # Browsers open a limited number of simultaneous connections to a single
    # host. The exact number varies by browser and version. This limit may cause
    # some asset downloads to wait for previous assets to finish before they can
    # begin. You can use the <tt>%d</tt> wildcard in the +asset_host+ to
    # distribute the requests over four hosts. For example,
    # <tt>assets%d.example.com<tt> will spread the asset requests over
    # "assets0.example.com", ..., "assets3.example.com".
    #
    #   image_tag("rails.png")
    #   # => <img alt="Rails" src="http://assets0.example.com/assets/rails.png" />
    #   stylesheet_link_tag("application")
    #   # => <link href="http://assets2.example.com/assets/application.css" media="screen" rel="stylesheet" />
    #
    # This may improve the asset loading performance of your application.
    # It is also possible the combination of additional connection overhead
    # (DNS, SSL) and the overall browser connection limits may result in this
    # solution being slower. You should be sure to measure your actual
    # performance across targeted browsers both before and after this change.
    #
    # To implement the corresponding hosts you can either setup four actual
    # hosts or use wildcard DNS to CNAME the wildcard to a single asset host.
    # You can read more about setting up your DNS CNAME records from your ISP.
    #
    # Note: This is purely a browser performance optimization and is not meant
    # for server load balancing. See http://www.die.net/musings/page_load_time/
    # for background and http://www.browserscope.org/?category=network for
    # connection limit data.
    #
    # Alternatively, you can exert more control over the asset host by setting
    # +asset_host+ to a proc like this:
    #
    #   ActionController::Base.asset_host = Proc.new { |source|
    #     "http://assets#{Digest::MD5.hexdigest(source).to_i(16) % 2 + 1}.example.com"
    #   }
    #   image_tag("rails.png")
    #   # => <img alt="Rails" src="http://assets1.example.com/assets/rails.png" />
    #   stylesheet_link_tag("application")
    #   # => <link href="http://assets2.example.com/assets/application.css" media="screen" rel="stylesheet" />
    #
    # The example above generates "http://assets1.example.com" and
    # "http://assets2.example.com". This option is useful for example if
    # you need fewer/more than four hosts, custom host names, etc.
    #
    # As you see the proc takes a +source+ parameter. That's a string with the
    # absolute path of the asset, for example "/assets/rails.png".
    #
    #    ActionController::Base.asset_host = Proc.new { |source|
    #      if source.ends_with?('.css')
    #        "http://stylesheets.example.com"
    #      else
    #        "http://assets.example.com"
    #      end
    #    }
    #   image_tag("rails.png")
    #   # => <img alt="Rails" src="http://assets.example.com/assets/rails.png" />
    #   stylesheet_link_tag("application")
    #   # => <link href="http://stylesheets.example.com/assets/application.css" media="screen" rel="stylesheet" />
    #
    # Alternatively you may ask for a second parameter +request+. That one is
    # particularly useful for serving assets from an SSL-protected page. The
    # example proc below disables asset hosting for HTTPS connections, while
    # still sending assets for plain HTTP requests from asset hosts. If you don't
    # have SSL certificates for each of the asset hosts this technique allows you
    # to avoid warnings in the client about mixed media.
    # Note that the request parameter might not be supplied, e.g. when the assets
    # are precompiled via a Rake task. Make sure to use a Proc instead of a lambda,
    # since a Proc allows missing parameters and sets them to nil.
    #
    #   config.action_controller.asset_host = Proc.new { |source, request|
    #     if request && request.ssl?
    #       "#{request.protocol}#{request.host_with_port}"
    #     else
    #       "#{request.protocol}assets.example.com"
    #     end
    #   }
    #
    # You can also implement a custom asset host object that responds to +call+
    # and takes either one or two parameters just like the proc.
    #
    #   config.action_controller.asset_host = AssetHostingWithMinimumSsl.new(
    #     "http://asset%d.example.com", "https://asset1.example.com"
    #   )
    #
    module AssetUrlHelper
      URI_REGEXP = %r{^[-a-z]+://|^(?:cid|data):|^//}i

      # Computes the path to asset in public directory. If :type
      # options is set, a file extension will be appended and scoped
      # to the corresponding public directory.
      #
      # All other asset *_path helpers delegate through this method.
      #
      #   asset_path "application.js"                     # => /assets/application.js
      #   asset_path "application", type: :javascript     # => /assets/application.js
      #   asset_path "application", type: :stylesheet     # => /assets/application.css
      #   asset_path "http://www.example.com/js/xmlhr.js" # => http://www.example.com/js/xmlhr.js
      def asset_path(source, options = {})
        raise ArgumentError, "nil is not a valid asset source" if source.nil?

        source = source.to_s
        return "" if source.blank?
        return source if URI_REGEXP.match?(source)

        tail, source = source[/([\?#].+)$/], source.sub(/([\?#].+)$/, "".freeze)

        if extname = compute_asset_extname(source, options)
          source = "#{source}#{extname}"
        end

        if options[:public_folder]
          source = public_compute_asset_path(source, options) unless options[:raw]
        else
          if source[0] != ?/
            source = compute_asset_path(source, options) unless options[:raw]
          elsif !options[:raw]
            message =  "Skipping computing asset path since asset #{ source.inspect } starts with a slash `/`.\n"
            message << "This behavior is deprecated and will be removed. Instead explicitly\n"
            message << "use a `public_*` helper instead. Optionally pass in `raw: true` to get the exact same behavior."
            ActiveSupport::Deprecation.warn(message)
          end
        end

        relative_url_root = defined?(config.relative_url_root) && config.relative_url_root
        if relative_url_root
          source = File.join(relative_url_root, source) unless source.starts_with?("#{relative_url_root}/")
        end

        if host = compute_asset_host(source, options)
          source = File.join(host, source)
        end

        "#{source}#{tail}"
      end
      alias_method :path_to_asset, :asset_path # aliased to avoid conflicts with an asset_path named route


      def public_asset_path(source, options = {})
        path_to_asset(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_asset, :public_asset_path # aliased to avoid conflicts with an font_path named route

      # Computes the full URL to an asset in the public directory. This
      # will use +asset_path+ internally, so most of their behaviors
      # will be the same. If :host options is set, it overwrites global
      # +config.action_controller.asset_host+ setting.
      #
      # All other options provided are forwarded to +asset_path+ call.
      #
      #   asset_url "application.js"                                 # => http://example.com/assets/application.js
      #   asset_url "application.js", host: "http://cdn.example.com" # => http://cdn.example.com/assets/application.js
      #
      def asset_url(source, options = {})
        path_to_asset(source, options.merge(protocol: :request))
      end
      alias_method :url_to_asset, :asset_url # aliased to avoid conflicts with an asset_url named route

      # Computes the full URL to a asset in the public folder.
      # This uses +asset_url+ and skips any asset lookups by assuming the asset is in the
      # `public` folder.
      def public_asset_url(source, options = {})
        url_to_asset(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_asset, :public_asset_path # aliased to avoid conflicts with an asset_path named route

      ASSET_EXTENSIONS = {
        javascript: ".js",
        stylesheet: ".css"
      }

      # Compute extname to append to asset path. Returns nil if
      # nothing should be added.
      def compute_asset_extname(source, options = {})
        return if options[:extname] == false
        extname = options[:extname] || ASSET_EXTENSIONS[options[:type]]
        extname if extname && File.extname(source) != extname
      end

      # Maps asset types to public directory.
      ASSET_PUBLIC_DIRECTORIES = {
        audio:      "/audios",
        font:       "/fonts",
        image:      "/images",
        javascript: "/javascripts",
        stylesheet: "/stylesheets",
        video:      "/videos"
      }

      # Computes asset path to public directory. Plugins and
      # extensions can override this method to point to custom assets
      # or generate digested paths or query strings.
      def compute_asset_path(source, options = {})
        dir = ASSET_PUBLIC_DIRECTORIES[options[:type]] || ""
        File.join(dir, source)
      end
      alias :public_compute_asset_path :compute_asset_path

      # Pick an asset host for this source. Returns +nil+ if no host is set,
      # the host if no wildcard is set, the host interpolated with the
      # numbers 0-3 if it contains <tt>%d</tt> (the number is the source hash mod 4),
      # or the value returned from invoking call on an object responding to call
      # (proc or otherwise).
      def compute_asset_host(source = "", options = {})
        request = self.request if respond_to?(:request)
        host = options[:host]
        host ||= config.asset_host if defined? config.asset_host

        if host
          if host.respond_to?(:call)
            arity = host.respond_to?(:arity) ? host.arity : host.method(:call).arity
            args = [source]
            args << request if request && (arity > 1 || arity < 0)
            host = host.call(*args)
          elsif host.include?("%d")
            host = host % (Zlib.crc32(source) % 4)
          end
        end

        host ||= request.base_url if request && options[:protocol] == :request
        return unless host

        if URI_REGEXP.match?(host)
          host
        else
          protocol = options[:protocol] || config.default_asset_host_protocol || (request ? :request : :relative)
          case protocol
          when :relative
            "//#{host}"
          when :request
            "#{request.protocol}#{host}"
          else
            "#{protocol}://#{host}"
          end
        end
      end

      # Computes the path to a JavaScript asset in the public javascripts directory.
      # If the +source+ filename has no extension, .js will be appended (except for explicit URIs)
      # Full paths from the document root will be passed through.
      # Used internally by +javascript_include_tag+ to build the script path.
      #
      #   javascript_path "xmlhr"                              # => /assets/xmlhr.js
      #   javascript_path "dir/xmlhr.js"                       # => /assets/dir/xmlhr.js
      #   javascript_path "/dir/xmlhr"                         # => /dir/xmlhr.js
      #   javascript_path "http://www.example.com/js/xmlhr"    # => http://www.example.com/js/xmlhr
      #   javascript_path "http://www.example.com/js/xmlhr.js" # => http://www.example.com/js/xmlhr.js
      def javascript_path(source, options = {})
        path_to_asset(source, { type: :javascript }.merge!(options))
      end
      alias_method :path_to_javascript, :javascript_path # aliased to avoid conflicts with a javascript_path named route

      def public_javascript_path(source, options = {})
        path_to_javascript(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_javascript, :public_javascript_path # aliased to avoid conflicts with an font_path named route

      # Computes the full URL to a JavaScript asset in the public javascripts directory.
      # This will use +javascript_path+ internally, so most of their behaviors will be the same.
      # Since +javascript_url+ is based on +asset_url+ method you can set :host options. If :host
      # options is set, it overwrites global +config.action_controller.asset_host+ setting.
      #
      #   javascript_url "js/xmlhr.js", host: "http://stage.example.com" # => http://stage.example.com/assets/dir/xmlhr.js
      #
      def javascript_url(source, options = {})
        url_to_asset(source, { type: :javascript }.merge!(options))
      end
      alias_method :url_to_javascript, :javascript_url # aliased to avoid conflicts with a javascript_url named route

      # Computes the full URL to a javascript asset in the public folder.
      # This uses +javascript_url+ and skips any asset lookups by assuming the asset is in the
      # `public` folder.
      def public_javascript_url(source, options = {})
        url_to_javascript(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_javascript, :public_javascript_path # aliased to avoid conflicts with an javascript_path named route

      # Computes the path to a stylesheet asset in the public stylesheets directory.
      # If the +source+ filename has no extension, .css will be appended (except for explicit URIs).
      # Full paths from the document root will be passed through.
      # Used internally by +stylesheet_link_tag+ to build the stylesheet path.
      #
      #   stylesheet_path "style"                                  # => /assets/style.css
      #   stylesheet_path "dir/style.css"                          # => /assets/dir/style.css
      #   stylesheet_path "/dir/style.css"                         # => /dir/style.css
      #   stylesheet_path "http://www.example.com/css/style"       # => http://www.example.com/css/style
      #   stylesheet_path "http://www.example.com/css/style.css"   # => http://www.example.com/css/style.css
      def stylesheet_path(source, options = {})
        path_to_asset(source, { type: :stylesheet }.merge!(options))
      end
      alias_method :path_to_stylesheet, :stylesheet_path # aliased to avoid conflicts with a stylesheet_path named route

      def public_stylesheet_path(source, options)
        path_to_stylesheet(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_stylesheet, :public_stylesheet_path # aliased to avoid conflicts with an font_path named route

      # Computes the full URL to a stylesheet asset in the public stylesheets directory.
      # This will use +stylesheet_path+ internally, so most of their behaviors will be the same.
      # Since +stylesheet_url+ is based on +asset_url+ method you can set :host options. If :host
      # options is set, it overwrites global +config.action_controller.asset_host+ setting.
      #
      #   stylesheet_url "css/style.css", host: "http://stage.example.com" # => http://stage.example.com/css/style.css
      #
      def stylesheet_url(source, options = {})
        url_to_asset(source, { type: :stylesheet }.merge!(options))
      end
      alias_method :url_to_stylesheet, :stylesheet_url # aliased to avoid conflicts with a stylesheet_url named route

      # Computes the full URL to a stylesheet asset in the public folder.
      # This uses +stylesheet_url+ and skips any asset lookups by assuming the asset is in the
      # `public` folder.
      def public_stylesheet_url(source, options = {})
        url_to_stylesheet(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_stylesheet, :public_stylesheet_path # aliased to avoid conflicts with an stylesheet_path named route

      # Computes the path to an image asset.
      # Full paths from the document root will be passed through.
      # Used internally by +image_tag+ to build the image path:
      #
      #   image_path("edit")                                         # => "/assets/edit"
      #   image_path("edit.png")                                     # => "/assets/edit.png"
      #   image_path("icons/edit.png")                               # => "/assets/icons/edit.png"
      #   image_path("/icons/edit.png")                              # => "/icons/edit.png"
      #   image_path("http://www.example.com/img/edit.png")          # => "http://www.example.com/img/edit.png"
      #
      # If you have images as application resources this method may conflict with their named routes.
      # The alias +path_to_image+ is provided to avoid that. Rails uses the alias internally, and
      # plugin authors are encouraged to do so.
      def image_path(source, options = {})
        path_to_asset(source, { type: :image }.merge!(options))
      end
      alias_method :path_to_image, :image_path # aliased to avoid conflicts with an image_path named route

      def public_image_path(source, options)
        path_to_image(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_image, :public_image_path # aliased to avoid conflicts with an font_path named route

      # Computes the full URL to an image asset.
      # This will use +image_path+ internally, so most of their behaviors will be the same.
      # Since +image_url+ is based on +asset_url+ method you can set :host options. If :host
      # options is set, it overwrites global +config.action_controller.asset_host+ setting.
      #
      #   image_url "edit.png", host: "http://stage.example.com" # => http://stage.example.com/edit.png
      #
      def image_url(source, options = {})
        url_to_asset(source, { type: :image }.merge!(options))
      end
      alias_method :url_to_image, :image_url # aliased to avoid conflicts with an image_url named route

      # Computes the full URL to a image asset in the public folder.
      # This uses +image_url+ and skips any asset lookups by assuming the asset is in the
      # `public` folder.
      def public_image_url(source, options = {})
        url_to_image(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_image, :public_image_path # aliased to avoid conflicts with an image_path named route

      # Computes the path to a video asset in the public videos directory.
      # Full paths from the document root will be passed through.
      # Used internally by +video_tag+ to build the video path.
      #
      #   video_path("hd")                                            # => /videos/hd
      #   video_path("hd.avi")                                        # => /videos/hd.avi
      #   video_path("trailers/hd.avi")                               # => /videos/trailers/hd.avi
      #   video_path("/trailers/hd.avi")                              # => /trailers/hd.avi
      #   video_path("http://www.example.com/vid/hd.avi")             # => http://www.example.com/vid/hd.avi
      def video_path(source, options = {})
        path_to_asset(source, { type: :video }.merge!(options))
      end
      alias_method :path_to_video, :video_path # aliased to avoid conflicts with a video_path named route

      def public_video_path(source, options)
        path_to_video(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_video, :public_video_path # aliased to avoid conflicts with an font_path named route

      # Computes the full URL to a video asset in the public videos directory.
      # This will use +video_path+ internally, so most of their behaviors will be the same.
      # Since +video_url+ is based on +asset_url+ method you can set :host options. If :host
      # options is set, it overwrites global +config.action_controller.asset_host+ setting.
      #
      #   video_url "hd.avi", host: "http://stage.example.com" # => http://stage.example.com/hd.avi
      #
      def video_url(source, options = {})
        url_to_asset(source, { type: :video }.merge!(options))
      end
      alias_method :url_to_video, :video_url # aliased to avoid conflicts with an video_url named route

      # Computes the full URL to a video asset in the public folder.
      # This uses +video_url+ and skips any asset lookups by assuming the asset is in the
      # `public` folder.
      def public_video_url(source, options = {})
        url_to_video(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_video, :public_video_path # aliased to avoid conflicts with an video_path named route

      # Computes the path to an audio asset in the public audios directory.
      # Full paths from the document root will be passed through.
      # Used internally by +audio_tag+ to build the audio path.
      #
      #   audio_path("horse")                                            # => /audios/horse
      #   audio_path("horse.wav")                                        # => /audios/horse.wav
      #   audio_path("sounds/horse.wav")                                 # => /audios/sounds/horse.wav
      #   audio_path("/sounds/horse.wav")                                # => /sounds/horse.wav
      #   audio_path("http://www.example.com/sounds/horse.wav")          # => http://www.example.com/sounds/horse.wav
      def audio_path(source, options = {})
        path_to_asset(source, { type: :audio }.merge!(options))
      end
      alias_method :path_to_audio, :audio_path # aliased to avoid conflicts with an audio_path named route

      def public_audio_path(source, options = {})
        path_to_audio(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_audio, :public_audio_path # aliased to avoid conflicts with an font_path named route

      # Computes the full URL to an audio asset in the public audios directory.
      # This will use +audio_path+ internally, so most of their behaviors will be the same.
      # Since +audio_url+ is based on +asset_url+ method you can set :host options. If :host
      # options is set, it overwrites global +config.action_controller.asset_host+ setting.
      #
      #   audio_url "horse.wav", host: "http://stage.example.com" # => http://stage.example.com/horse.wav
      #
      def audio_url(source, options = {})
        url_to_asset(source, { type: :audio }.merge!(options))
      end
      alias_method :url_to_audio, :audio_url # aliased to avoid conflicts with an audio_url named route

      # Computes the full URL to a audio asset in the public folder.
      # This uses +audio_url+ and skips any asset lookups by assuming the asset is in the
      # `public` folder.
      def public_audio_url(source, options = {})
        url_to_audio(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_audio, :public_audio_path # aliased to avoid conflicts with an audio_path named route

      # Computes the path to a font asset.
      # Full paths from the document root will be passed through.
      #
      #   font_path("font")                                           # => /fonts/font
      #   font_path("font.ttf")                                       # => /fonts/font.ttf
      #   font_path("dir/font.ttf")                                   # => /fonts/dir/font.ttf
      #   font_path("/dir/font.ttf")                                  # => /dir/font.ttf
      #   font_path("http://www.example.com/dir/font.ttf")            # => http://www.example.com/dir/font.ttf
      def font_path(source, options = {})
        path_to_asset(source, { type: :font }.merge!(options))
      end
      alias_method :path_to_font, :font_path # aliased to avoid conflicts with an font_path named route

      def public_font_path(source, options = {})
        path_to_font(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_font, :public_font_path # aliased to avoid conflicts with an font_path named route

      # Computes the full URL to a font asset.
      # This will use +font_path+ internally, so most of their behaviors will be the same.
      # Since +font_url+ is based on +asset_url+ method you can set :host options. If :host
      # options is set, it overwrites global +config.action_controller.asset_host+ setting.
      #
      #   font_url "font.ttf", host: "http://stage.example.com" # => http://stage.example.com/font.ttf
      #
      def font_url(source, options = {})
        url_to_asset(source, { type: :font }.merge!(options))
      end
      alias_method :url_to_font, :font_url # aliased to avoid conflicts with an font_url named route

      # Computes the full URL to a font asset in the public folder.
      # This uses +font_url+ and skips any asset lookups by assuming the asset is in the
      # `public` folder.
      def public_font_url(source, options = {})
        url_to_font(source, {public_folder: true}.merge!(options))
      end
      alias_method :path_to_public_font, :public_font_path # aliased to avoid conflicts with an public_font_url named route
    end
  end
end
