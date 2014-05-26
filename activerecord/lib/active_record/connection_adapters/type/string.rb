module ActiveRecord
  module ConnectionAdapters
    module Type
      class String < Value
        def type
          :string
        end

        def text?
          true
        end

        def klass
          ::String
        end

        private

        def cast_value(value)
          case value
          when true then "1"
          when false then "0"
          else value.to_s
          end
        end
      end
    end
  end
end
