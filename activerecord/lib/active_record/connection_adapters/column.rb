require 'set'

module ActiveRecord
  # :stopdoc:
  module ConnectionAdapters
    # An abstract definition of a column in a table.
    class Column
      TRUE_VALUES = [true, 1, '1', 't', 'T', 'true', 'TRUE', 'on', 'ON'].to_set
      FALSE_VALUES = [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF'].to_set

      module Format
        ISO_DATE = /\A(\d{4})-(\d\d)-(\d\d)\z/
        ISO_DATETIME = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(\.\d+)?\z/
      end

      attr_reader :name, :default, :cast_type, :limit, :null, :sql_type, :precision, :scale, :default_function
      attr_accessor :primary, :coder

      alias :encoded? :coder

      delegate :type, to: :cast_type

      # Instantiates a new column in the table.
      #
      # +name+ is the column's name, such as <tt>supplier_id</tt> in <tt>supplier_id int(11)</tt>.
      # +default+ is the type-casted default value, such as +new+ in <tt>sales_stage varchar(20) default 'new'</tt>.
      # +cast_type+ is the object used for type casting and type information.
      # +sql_type+ is used to extract the column's length, if necessary. For example +60+ in
      # <tt>company_name varchar(60)</tt>.
      # It will be mapped to one of the standard Rails SQL types in the <tt>type</tt> attribute.
      # +null+ determines if this column allows +NULL+ values.
      def initialize(name, default, cast_type, sql_type = nil, null = true)
        @name             = name
        @cast_type        = cast_type
        @sql_type         = sql_type
        @null             = null
        @limit            = extract_limit(sql_type)
        @precision        = extract_precision(sql_type)
        @scale            = extract_scale(sql_type)
        @default          = extract_default(default)
        @default_function = nil
        @primary          = nil
        @coder            = nil
      end

      # Returns +true+ if the column is either of type string or text.
      def text?
        type == :string || type == :text
      end

      # Returns +true+ if the column is either of type integer, float or decimal.
      def number?
        type == :integer || type == :float || type == :decimal
      end

      def has_default?
        !default.nil?
      end

      # Returns the Ruby class that corresponds to the abstract data type.
      def klass
        case type
        when :integer                     then Fixnum
        when :float                       then Float
        when :decimal                     then BigDecimal
        when :datetime, :timestamp, :time then Time
        when :date                        then Date
        when :text, :string, :binary      then String
        when :boolean                     then Object
        end
      end

      def binary?
        type == :binary
      end

      # Casts a Ruby value to something appropriate for writing to the database.
      # Numeric columns will typecast boolean and string to appropriate numeric
      # values.
      def type_cast_for_write(value)
        return value unless number?

        case value
        when FalseClass
          0
        when TrueClass
          1
        when String
          value.presence
        else
          value
        end
      end

      # Casts value to an appropriate instance.
      def type_cast(value)
        return nil if value.nil?
        return coder.load(value) if encoded?

        klass = self.class

        case type
        when :string, :text
          case value
          when TrueClass; "1"
          when FalseClass; "0"
          else
            value.to_s
          end
        when :integer              then klass.value_to_integer(value)
        when :float                then value.to_f
        when :decimal              then klass.value_to_decimal(value)
        when :datetime, :timestamp then klass.string_to_time(value)
        when :time                 then klass.string_to_dummy_time(value)
        when :date                 then klass.value_to_date(value)
        when :binary               then klass.binary_to_string(value)
        when :boolean              then klass.value_to_boolean(value)
        else value
        end
      end

      # Returns the human name of the column name.
      #
      # ===== Examples
      #  Column.new('sales_stage', ...).human_name # => 'Sales stage'
      def human_name
        Base.human_attribute_name(@name)
      end

      def extract_default(default)
        type_cast(default)
      end

      class << self
        # Used to convert from BLOBs to Strings
        def binary_to_string(value)
          value
        end

        def value_to_date(value)
          if value.is_a?(String)
            return nil if value.empty?
            fast_string_to_date(value) || fallback_string_to_date(value)
          elsif value.respond_to?(:to_date)
            value.to_date
          else
            value
          end
        end

        def string_to_time(string)
          return string unless string.is_a?(String)
          return nil if string.empty?

          fast_string_to_time(string) || fallback_string_to_time(string)
        end

        def string_to_dummy_time(string)
          return string unless string.is_a?(String)
          return nil if string.empty?

          dummy_time_string = "2000-01-01 #{string}"

          fast_string_to_time(dummy_time_string) || begin
            time_hash = Date._parse(dummy_time_string)
            return nil if time_hash[:hour].nil?
            new_time(*time_hash.values_at(:year, :mon, :mday, :hour, :min, :sec, :sec_fraction))
          end
        end

        # convert something to a boolean
        def value_to_boolean(value)
          if value.is_a?(String) && value.empty?
            nil
          else
            TRUE_VALUES.include?(value)
          end
        end

        # Used to convert values to integer.
        # handle the case when an integer column is used to store boolean values
        def value_to_integer(value)
          case value
          when TrueClass, FalseClass
            value ? 1 : 0
          else
            value.to_i rescue nil
          end
        end

        # convert something to a BigDecimal
        def value_to_decimal(value)
          # Using .class is faster than .is_a? and
          # subclasses of BigDecimal will be handled
          # in the else clause
          if value.class == BigDecimal
            value
          elsif value.respond_to?(:to_d)
            value.to_d
          else
            value.to_s.to_d
          end
        end

        protected
          # '0.123456' -> 123456
          # '1.123456' -> 123456
          def microseconds(time)
            time[:sec_fraction] ? (time[:sec_fraction] * 1_000_000).to_i : 0
          end

          def new_date(year, mon, mday)
            if year && year != 0
              Date.new(year, mon, mday) rescue nil
            end
          end

          def new_time(year, mon, mday, hour, min, sec, microsec, offset = nil)
            # Treat 0000-00-00 00:00:00 as nil.
            return nil if year.nil? || (year == 0 && mon == 0 && mday == 0)

            if offset
              time = Time.utc(year, mon, mday, hour, min, sec, microsec) rescue nil
              return nil unless time

              time -= offset
              Base.default_timezone == :utc ? time : time.getlocal
            else
              Time.public_send(Base.default_timezone, year, mon, mday, hour, min, sec, microsec) rescue nil
            end
          end

          def fast_string_to_date(string)
            if string =~ Format::ISO_DATE
              new_date $1.to_i, $2.to_i, $3.to_i
            end
          end

          # Doesn't handle time zones.
          def fast_string_to_time(string)
            if string =~ Format::ISO_DATETIME
              microsec = ($7.to_r * 1_000_000).to_i
              new_time $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, microsec
            end
          end

          def fallback_string_to_date(string)
            new_date(*::Date._parse(string, false).values_at(:year, :mon, :mday))
          end

          def fallback_string_to_time(string)
            time_hash = Date._parse(string)
            time_hash[:sec_fraction] = microseconds(time_hash)

            new_time(*time_hash.values_at(:year, :mon, :mday, :hour, :min, :sec, :sec_fraction, :offset))
          end
      end

      private
        delegate :extract_scale, to: Type

        def extract_limit(sql_type)
          $1.to_i if sql_type =~ /\((.*)\)/
        end

        def extract_precision(sql_type)
          $2.to_i if sql_type =~ /^(numeric|decimal|number)\((\d+)(,\d+)?\)/i
        end
    end
  end
  # :startdoc:
end
