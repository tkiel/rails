# frozen_string_literal: true

module ActiveJob
  module Serializers
    # Provides methods to serialize and deserialize `ActiveSupport::HashWithIndifferentAccess`
    # Values will be serialized by known serializers
    class HashWithIndifferentAccessSerializer < HashSerializer # :nodoc:
      def serialize(hash)
        result = serialize_hash(hash)
        result[key] = Serializers.serialize(true)
        result
      end

      def deserialize(hash)
        result = hash.transform_values { |v| Serializers.deserialize(v) }
        result.delete(key)
        result.with_indifferent_access
      end

      private

        def key
          WITH_INDIFFERENT_ACCESS_KEY
        end

        def klass
          ActiveSupport::HashWithIndifferentAccess
        end
    end
  end
end
