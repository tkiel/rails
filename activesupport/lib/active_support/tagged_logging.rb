require 'active_support/core_ext/object/blank'
require 'logger'

module ActiveSupport
  # Wraps any standard Logger object to provide tagging capabilities. Examples:
  #
  #   LOGGER = ActiveSupport::TaggedLogging.new(Logger.new(STDOUT))
  #   LOGGER.tagged("BCX") { LOGGER.info "Stuff" }                            # Logs "[BCX] Stuff"
  #   LOGGER.tagged("BCX", "Jason") { LOGGER.info "Stuff" }                   # Logs "[BCX] [Jason] Stuff"
  #   LOGGER.tagged("BCX") { LOGGER.tagged("Jason") { LOGGER.info "Stuff" } } # Logs "[BCX] [Jason] Stuff"
  #
  # This is used by the default Rails.logger as configured by Railties to make it easy to stamp log lines
  # with subdomains, request ids, and anything else to aid debugging of multi-user production applications.
  class TaggedLogging
    def initialize(logger)
      @logger = logger
    end

    def tagged(*new_tags)
      tags     = current_tags
      new_tags = Array(new_tags).flatten.reject(&:blank?)
      tags.concat new_tags
      yield
    ensure
      tags.pop(new_tags.size)
    end

    def add(severity, message = nil, progname = nil, &block)
      @logger.add(severity, "#{tags_text}#{message}", progname, &block)
    end

    %w( fatal error warn info debug unknown ).each do |severity|
      eval <<-EOM, nil, __FILE__, __LINE__ + 1
        def #{severity}(progname = nil, &block)              # def warn(progname = nil, &block)
          add(Logger::#{severity.upcase}, progname, &block)  #   add(Logger::WARN, progname, &block)
        end                                                  # end
      EOM
    end

    def flush
      current_tags.clear
      @logger.flush if @logger.respond_to?(:flush)
    end

    def method_missing(method, *args)
      @logger.send(method, *args)
    end

    protected

    def tags_text
      tags = current_tags
      if tags.any?
        tags.collect { |tag| "[#{tag}] " }.join
      end
    end

    def current_tags
      Thread.current[:activesupport_tagged_logging_tags] ||= []
    end
  end
end
