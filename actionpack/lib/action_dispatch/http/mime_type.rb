require 'singleton'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/string/starts_ends_with'
require 'active_support/deprecation'

module Mime
  class Mimes
    include Enumerable

    def initialize
      @mimes = []
      @symbols = nil
    end

    def each
      @mimes.each { |x| yield x }
    end

    def <<(type)
      @mimes << type
      @symbols = nil
    end

    def delete_if
      @mimes.delete_if { |x| yield x }.tap { @symbols = nil }
    end

    def symbols
      @symbols ||= map(&:to_sym)
    end
  end

  SET              = Mimes.new
  EXTENSION_LOOKUP = {}
  LOOKUP           = Hash.new { |h, k| h[k] = Type.new(k) unless k.blank? }

  class << self
    def [](type)
      return type if type.is_a?(Type)
      Type.lookup_by_extension(type)
    end

    def fetch(type)
      return type if type.is_a?(Type)
      EXTENSION_LOOKUP.fetch(type.to_s) { |k| yield k }
    end

    def const_missing(sym)
      if Mime::Type.registered?(sym)
        ActiveSupport::Deprecation.warn <<-eow
Accessing mime types via constants is deprecated.  Please change:

  `Mime::#{sym}`

to:

  `Mime::Type[:#{sym}]`
        eow
        Mime::Type[sym]
      else
        super
      end
    end

    def const_defined?(sym, inherit = true)
      if Mime::Type.registered?(sym)
        ActiveSupport::Deprecation.warn <<-eow
Accessing mime types via constants is deprecated.  Please change:

  `Mime.const_defined?(#{sym})`

to:

  `Mime::Type.registered?(:#{sym})`
        eow
        true
      else
        super
      end
    end
  end

  # Encapsulates the notion of a mime type. Can be used at render time, for example, with:
  #
  #   class PostsController < ActionController::Base
  #     def show
  #       @post = Post.find(params[:id])
  #
  #       respond_to do |format|
  #         format.html
  #         format.ics { render body: @post.to_ics, mime_type: Mime::Type.lookup("text/calendar")  }
  #         format.xml { render xml: @post }
  #       end
  #     end
  #   end
  class Type
    attr_reader :symbol

    @register_callbacks = []

    # A simple helper class used in parsing the accept header
    class AcceptItem #:nodoc:
      attr_accessor :index, :name, :q
      alias :to_s :name

      def initialize(index, name, q = nil)
        @index = index
        @name = name
        q ||= 0.0 if @name == Mime::Type[:ALL].to_s # default wildcard match to end of list
        @q = ((q || 1.0).to_f * 100).to_i
      end

      def <=>(item)
        result = item.q <=> @q
        result = @index <=> item.index if result == 0
        result
      end

      def ==(item)
        @name == item.to_s
      end
    end

    class AcceptList < Array #:nodoc:
      def assort!
        sort!

        # Take care of the broken text/xml entry by renaming or deleting it
        if text_xml_idx && app_xml_idx
          app_xml.q = [text_xml.q, app_xml.q].max # set the q value to the max of the two
          exchange_xml_items if app_xml_idx > text_xml_idx  # make sure app_xml is ahead of text_xml in the list
          delete_at(text_xml_idx)                 # delete text_xml from the list
        elsif text_xml_idx
          text_xml.name = Mime::XML.to_s
        end

        # Look for more specific XML-based types and sort them ahead of app/xml
        if app_xml_idx
          idx = app_xml_idx

          while idx < length
            type = self[idx]
            break if type.q < app_xml.q

            if type.name.ends_with? '+xml'
              self[app_xml_idx], self[idx] = self[idx], app_xml
              @app_xml_idx = idx
            end
            idx += 1
          end
        end

        map! { |i| Mime::Type.lookup(i.name) }.uniq!
        to_a
      end

      private
        def text_xml_idx
          @text_xml_idx ||= index('text/xml')
        end

        def app_xml_idx
          @app_xml_idx ||= index(Mime::Type[:XML].to_s)
        end

        def text_xml
          self[text_xml_idx]
        end

        def app_xml
          self[app_xml_idx]
        end

        def exchange_xml_items
          self[app_xml_idx], self[text_xml_idx] = text_xml, app_xml
          @app_xml_idx, @text_xml_idx = text_xml_idx, app_xml_idx
        end
    end

    TYPES = {}

    class << self
      TRAILING_STAR_REGEXP = /(text|application)\/\*/
      PARAMETER_SEPARATOR_REGEXP = /;\s*\w+="?\w+"?/

      def register_callback(&block)
        @register_callbacks << block
      end

      def registered?(symbol)
        TYPES.key? symbol
      end

      def [](symbol)
        TYPES[symbol]
      end

      def add_type(symbol, type)
        TYPES[symbol] = type
      end

      def lookup(string)
        LOOKUP[string]
      end

      def lookup_by_extension(extension)
        EXTENSION_LOOKUP[extension.to_s]
      end

      # Registers an alias that's not used on mime type lookup, but can be referenced directly. Especially useful for
      # rendering different HTML versions depending on the user agent, like an iPhone.
      def register_alias(string, symbol, extension_synonyms = [])
        register(string, symbol, [], extension_synonyms, true)
      end

      def register(string, symbol, mime_type_synonyms = [], extension_synonyms = [], skip_lookup = false)
        new_mime = Type.new(string, symbol, mime_type_synonyms)
        add_type symbol.upcase, new_mime

        SET << new_mime

        ([string] + mime_type_synonyms).each { |str| LOOKUP[str] = new_mime } unless skip_lookup
        ([symbol] + extension_synonyms).each { |ext| EXTENSION_LOOKUP[ext.to_s] = new_mime }

        @register_callbacks.each do |callback|
          callback.call(new_mime)
        end
        new_mime
      end

      def parse(accept_header)
        if !accept_header.include?(',')
          accept_header = accept_header.split(PARAMETER_SEPARATOR_REGEXP).first
          parse_trailing_star(accept_header) || [Mime::Type.lookup(accept_header)].compact
        else
          list, index = AcceptList.new, 0
          accept_header.split(',').each do |header|
            params, q = header.split(PARAMETER_SEPARATOR_REGEXP)
            if params.present?
              params.strip!

              params = parse_trailing_star(params) || [params]

              params.each do |m|
                list << AcceptItem.new(index, m.to_s, q)
                index += 1
              end
            end
          end
          list.assort!
        end
      end

      def parse_trailing_star(accept_header)
        parse_data_with_trailing_star($1) if accept_header =~ TRAILING_STAR_REGEXP
      end

      # For an input of <tt>'text'</tt>, returns <tt>[Mime::JSON, Mime::XML, Mime::ICS,
      # Mime::HTML, Mime::CSS, Mime::CSV, Mime::JS, Mime::YAML, Mime::TEXT]</tt>.
      #
      # For an input of <tt>'application'</tt>, returns <tt>[Mime::HTML, Mime::JS,
      # Mime::XML, Mime::YAML, Mime::ATOM, Mime::JSON, Mime::RSS, Mime::URL_ENCODED_FORM]</tt>.
      def parse_data_with_trailing_star(input)
        Mime::SET.select { |m| m =~ input }
      end

      # This method is opposite of register method.
      #
      # To unregister a MIME type:
      #
      #   Mime::Type.unregister(:mobile)
      def unregister(symbol)
        symbol = symbol.upcase
        mime = TYPES.delete symbol

        SET.delete_if { |v| v.eql?(mime) }
        LOOKUP.delete_if { |_,v| v.eql?(mime) }
        EXTENSION_LOOKUP.delete_if { |_,v| v.eql?(mime) }
      end
    end

    def initialize(string, symbol = nil, synonyms = [])
      @symbol, @synonyms = symbol, synonyms
      @string = string
    end

    def to_s
      @string
    end

    def to_str
      to_s
    end

    def to_sym
      @symbol
    end

    def ref
      symbol || to_s
    end

    def ===(list)
      if list.is_a?(Array)
        (@synonyms + [ self ]).any? { |synonym| list.include?(synonym) }
      else
        super
      end
    end

    def ==(mime_type)
      return false unless mime_type
      (@synonyms + [ self ]).any? do |synonym|
        synonym.to_s == mime_type.to_s || synonym.to_sym == mime_type.to_sym
      end
    end

    def =~(mime_type)
      return false if mime_type.blank?
      regexp = Regexp.new(Regexp.quote(mime_type.to_s))
      (@synonyms + [ self ]).any? do |synonym|
        synonym.to_s =~ regexp
      end
    end

    def html?
      symbol == :html || @string =~ /html/
    end

    def all?; false; end

    private

    def to_ary; end
    def to_a; end

    def method_missing(method, *args)
      if method.to_s.ends_with? '?'
        method[0..-2].downcase.to_sym == to_sym
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false) #:nodoc:
      method.to_s.ends_with? '?'
    end

    class All < Type
      def all?; true; end
      def html?; true; end
    end
  end

  class NullType
    include Singleton

    def nil?
      true
    end

    def ref; end

    def respond_to_missing?(method, include_private = false)
      method.to_s.ends_with? '?'
    end

    private
    def method_missing(method, *args)
      false if method.to_s.ends_with? '?'
    end
  end
end

require 'action_dispatch/http/mime_types'
