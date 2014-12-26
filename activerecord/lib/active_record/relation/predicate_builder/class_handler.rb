module ActiveRecord
  class PredicateBuilder
    class ClassHandler # :nodoc:
      def call(attribute, value)
        print_deprecation_warning
        attribute.eq(value.name)
      end

      private

      def print_deprecation_warning
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          Passing a class as a value in an Active Record query is deprecated and
          will be removed. Pass a string instead.
        MSG
      end
    end
  end
end
