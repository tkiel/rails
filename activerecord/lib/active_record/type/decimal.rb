module ActiveRecord
  module Type
    class Decimal < Value # :nodoc:
      include Numeric

      def type
        :decimal
      end

      def klass
        ::BigDecimal
      end

      private

      def cast_value(value)
        if value.respond_to?(:to_d)
          value.to_d
        else
          value.to_s.to_d
        end
      end
    end
  end
end
