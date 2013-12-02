require 'active_support/number_helper/number_converter'

module ActiveSupport
  module NumberHelper
    class NumberToDelimitedConverter < NumberConverter #:nodoc:

      self.need_valid_float = true

      DELIMITED_REGEX = /(\d)(?=(\d\d\d)+(?!\d))/

      def convert
        parts.join(options[:separator])
      end

      private

        def parts
          left, right = number.to_s.split('.')
          left.gsub!(DELIMITED_REGEX) { "#{$1}#{options[:delimiter]}" }
          [left, right].compact
        end

    end
  end
end
