module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module OID # :nodoc:
        class Hstore < Type::Value
          def type
            :hstore
          end

          def type_cast_for_write(value)
            # roundtrip to ensure uniform uniform types
            # TODO: This is not an efficient solution.
            cast_value(type_cast_for_database(value))
          end

          def type_cast_for_database(value)
            ConnectionAdapters::PostgreSQLColumn.hstore_to_string(value)
          end

          def cast_value(value)
            ConnectionAdapters::PostgreSQLColumn.string_to_hstore value
          end

          def accessor
            ActiveRecord::Store::StringKeyedHashAccessor
          end
        end
      end
    end
  end
end
