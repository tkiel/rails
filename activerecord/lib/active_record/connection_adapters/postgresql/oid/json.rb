module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module OID # :nodoc:
        class Json < Type::Value
          def type
            :json
          end

          def type_cast_for_write(value)
            ConnectionAdapters::PostgreSQLColumn.json_to_string(value)
          end

          def cast_value(value)
            ConnectionAdapters::PostgreSQLColumn.string_to_json value
          end

          def accessor
            ActiveRecord::Store::StringKeyedHashAccessor
          end
        end
      end
    end
  end
end
