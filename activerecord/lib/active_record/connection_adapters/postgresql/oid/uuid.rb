module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module OID # :nodoc:
        class Uuid < Type::Value # :nodoc:
          def type
            :uuid
          end

          def type_cast(value)
            value.presence
          end
        end
      end
    end
  end
end
