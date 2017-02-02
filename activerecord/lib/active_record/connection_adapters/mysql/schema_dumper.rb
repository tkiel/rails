module ActiveRecord
  module ConnectionAdapters
    module MySQL
      module ColumnDumper
        def column_spec_for_primary_key(column)
          spec = super
          if [:integer, :bigint].include?(schema_type(column)) && !column.auto_increment?
            spec[:default] ||= schema_default(column) || "nil"
          end
          spec[:unsigned] = "true" if column.unsigned?
          spec
        end

        def prepare_column_options(column)
          spec = super
          spec[:unsigned] = "true" if column.unsigned?

          if supports_virtual_columns? && column.virtual?
            spec[:as] = extract_expression_for_virtual_column(column)
            spec[:stored] = "true" if /\b(?:STORED|PERSISTENT)\b/.match?(column.extra)
            spec = { type: schema_type(column).inspect }.merge!(spec)
          end

          spec
        end

        def migration_keys
          super + [:unsigned]
        end

        private

          def default_primary_key?(column)
            super && column.auto_increment?
          end

          def schema_type(column)
            if column.sql_type == "tinyblob"
              :blob
            else
              super
            end
          end

          def schema_precision(column)
            super unless /time/.match?(column.sql_type) && column.precision == 0
          end

          def schema_collation(column)
            if column.collation && table_name = column.table_name
              @table_collation_cache ||= {}
              @table_collation_cache[table_name] ||= select_one("SHOW TABLE STATUS LIKE '#{table_name}'")["Collation"]
              column.collation.inspect if column.collation != @table_collation_cache[table_name]
            end
          end

          def extract_expression_for_virtual_column(column)
            if mariadb?
              create_table_info = create_table_info(column.table_name)
              if %r/#{quote_column_name(column.name)} #{Regexp.quote(column.sql_type)} AS \((?<expression>.+?)\) #{column.extra}/m =~ create_table_info
                $~[:expression].inspect
              end
            else
              sql = "SELECT generation_expression FROM information_schema.columns" \
                    " WHERE table_schema = #{quote(@config[:database])}" \
                    "   AND table_name = #{quote(column.table_name)}" \
                    "   AND column_name = #{quote(column.name)}"
              select_value(sql, "SCHEMA").inspect
            end
          end
      end
    end
  end
end
