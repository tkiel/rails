module ActiveRecord
  module ConnectionAdapters
    # PostgreSQL-specific extensions to column definitions in a table.
    class PostgreSQLColumn < Column #:nodoc:
      attr_reader :array, :oid, :fmod
      alias :array? :array

      def initialize(name, default, cast_type, sql_type = nil, null = true, default_function = nil, oid = nil, fmod = nil)
        if sql_type =~ /\[\]$/
          @array = true
          sql_type = sql_type[0..sql_type.length - 3]
        else
          @array = false
        end
        @oid = oid
        @fmod = fmod
        super(name, default, cast_type, sql_type, null, default_function)
      end

      def serial?
        default_function && default_function =~ /\Anextval\(.*\)\z/
      end
    end
  end
end
