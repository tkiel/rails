module ActiveRecord
  module ConnectionAdapters
    module Type
      class Float < Value # :nodoc:
        include Numeric

        def type
          :float
        end

        def klass
          ::Float
        end

        private

        def cast_value(value)
          value.to_f
        end
      end
    end
  end
end
