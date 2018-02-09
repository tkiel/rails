# frozen_string_literal: true

module ActiveJob
  # Raised when an exception is raised during job arguments deserialization.
  #
  # Wraps the original exception raised as +cause+.
  class DeserializationError < StandardError
    def initialize #:nodoc:
      super("Error while trying to deserialize arguments: #{$!.message}")
      set_backtrace $!.backtrace
    end
  end

  # Raised when an unsupported argument type is set as a job argument. We
  # currently support NilClass, Integer, Fixnum, Float, String, TrueClass, FalseClass,
  # Bignum, BigDecimal, and objects that can be represented as GlobalIDs (ex: Active Record).
  # Raised if you set the key for a Hash something else than a string or
  # a symbol. Also raised when trying to serialize an object which can't be
  # identified with a Global ID - such as an unpersisted Active Record model.
  class SerializationError < ArgumentError; end

  # The <tt>ActiveJob::Serializers</tt> module is used to store a list of known serializers
  # and to add new ones. It also has helpers to serialize/deserialize objects
  module Serializers
    extend ActiveSupport::Autoload
    extend ActiveSupport::Concern

    autoload :ArraySerializer
    autoload :BaseSerializer
    autoload :GlobalIDSerializer
    autoload :HashWithIndifferentAccessSerializer
    autoload :HashSerializer
    autoload :ObjectSerializer
    autoload :StandardTypeSerializer

    mattr_accessor :_additional_serializers
    self._additional_serializers = []

    class << self
      # Returns serialized representative of the passed object.
      # Will look up through all known serializers.
      # Raises `ActiveJob::SerializationError` if it can't find a proper serializer.
      def serialize(argument)
        serializer = serializers.detect { |s| s.serialize?(argument) }
        raise SerializationError.new("Unsupported argument type: #{argument.class.name}") unless serializer
        serializer.serialize(argument)
      end

      # Returns deserialized object.
      # Will look up through all known serializers.
      # If no serializers found will raise `ArgumentError`
      def deserialize(argument)
        serializer = serializers.detect { |s| s.deserialize?(argument) }
        raise ArgumentError, "Can only deserialize primitive arguments: #{argument.inspect}" unless serializer
        serializer.deserialize(argument)
      end

      # Returns list of known serializers
      def serializers
        self._additional_serializers
      end

      # Adds a new serializer to a list of known serializers
      def add_serializers(*new_serializers)
        check_duplicate_serializer_keys!(new_serializers)

        self._additional_serializers = new_serializers + self._additional_serializers
      end

      # Returns a list of reserved keys, which cannot be used as keys for a hash
      def reserved_serializers_keys
        serializers.select { |s| s.respond_to?(:key) }.map(&:key)
      end

      private

        def check_duplicate_serializer_keys!(serializers)
          keys_to_add = serializers.select { |s| s.respond_to?(:key) }.map(&:key)

          duplicate_keys = reserved_serializers_keys & keys_to_add

          raise ArgumentError.new("Can't add serializers because of keys duplication: #{duplicate_keys}") if duplicate_keys.any?
        end
    end

    add_serializers GlobalIDSerializer,
      StandardTypeSerializer,
      HashWithIndifferentAccessSerializer,
      HashSerializer,
      ArraySerializer
  end
end
