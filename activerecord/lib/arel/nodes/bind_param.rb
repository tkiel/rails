# frozen_string_literal: true

module Arel # :nodoc: all
  module Nodes
    class BindParam < Node
      attr_reader :value

      def initialize(value)
        @value = value
        super()
      end

      def hash
        [self.class, self.value].hash
      end

      def eql?(other)
        other.is_a?(BindParam) &&
          value == other.value
      end
      alias :== :eql?

      def nil?
        value.nil?
      end

      def boundable?
        !value.respond_to?(:boundable?) || value.boundable?
      end
    end
  end
end
