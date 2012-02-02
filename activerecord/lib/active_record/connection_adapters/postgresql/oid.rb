require 'active_record/connection_adapters/abstract_adapter'

module ActiveRecord
  module ConnectionAdapters
    class PostgreSQLAdapter < AbstractAdapter
      module OID
        class Wtf
          def type_cast(value)
            p :wtf => value
            value
          end
        end

        class Identity
          def type_cast(value)
            value
          end
        end

        class Bytea
          def type_cast(value)
            PGconn.unescape_bytea value if value
          end
        end

        class Money
          def type_cast(value)
            # Because money output is formatted according to the locale, there are two
            # cases to consider (note the decimal separators):
            #  (1) $12,345,678.12
            #  (2) $12.345.678,12

            case value
            when /^-?\D+[\d,]+\.\d{2}$/  # (1)
              value.gsub!(/[^-\d.]/, '')
            when /^-?\D+[\d.]+,\d{2}$/  # (2)
              value.gsub!(/[^-\d,]/, '').sub!(/,/, '.')
            end

            ConnectionAdapters::Column.value_to_decimal value
          end
        end

        class Vector
          attr_reader :delim, :subtype

          # +delim+ corresponds to the `typdelim` column in the pg_types
          # table.  +subtype+ is derived from the `typelem` column in the
          # pg_types table.
          def initialize(delim, subtype)
            @delim   = delim
            @subtype = subtype
          end

          # FIXME: this should probably split on +delim+ and use +subtype+
          # to cast the values.  Unfortunately, the current Rails behavior
          # is to just return the string.
          def type_cast(value)
            value
          end
        end

        class Integer
          def type_cast(value)
            value.to_i
          end
        end

        class Boolean
          def type_cast(value)
            value == 't'
          end
        end

        class Timestamp
          def type_cast(value)
            # FIXME: probably we can improve this since we know it is PG
            # specific
            ConnectionAdapters::Column.string_to_time value
          end
        end

        class Date
          def type_cast(value)
            # FIXME: probably we can improve this since we know it is PG
            # specific
            ConnectionAdapters::Column.value_to_date value
          end
        end

        class Time
          def type_cast(value)
            # FIXME: probably we can improve this since we know it is PG
            # specific
            ConnectionAdapters::Column.string_to_dummy_time value
          end
        end

        class Float
          def type_cast(value)
            value.to_f
          end
        end

        TYPE_MAP = {} # :nodoc:

        TYPE_MAP[23] = OID::Integer.new  # int4
        TYPE_MAP[20] = TYPE_MAP[23] # int8
        TYPE_MAP[21] = TYPE_MAP[23] # int2
        TYPE_MAP[26] = TYPE_MAP[23] # oid

        TYPE_MAP[25]   = OID::Identity.new # text
        TYPE_MAP[19]   = TYPE_MAP[25] # name
        TYPE_MAP[1043] = TYPE_MAP[25] # varchar

        # FIXME: why are we keeping these types as strings?
        TYPE_MAP[3614] = TYPE_MAP[25] # tsvector
        TYPE_MAP[1186] = TYPE_MAP[25] # interval
        TYPE_MAP[650]  = TYPE_MAP[25] # cidr
        TYPE_MAP[869]  = TYPE_MAP[25] # inet
        TYPE_MAP[829]  = TYPE_MAP[25] # macaddr
        TYPE_MAP[1560] = TYPE_MAP[25] # bit
        TYPE_MAP[1562] = TYPE_MAP[25] # varbit

        # FIXME: I don't think this is correct. We should probably be returning a parsed date,
        # but the tests pass with a string returned.
        TYPE_MAP[1184] = OID::Identity.new # timestamptz

        TYPE_MAP[790] = OID::Money.new # money
        TYPE_MAP[17]  = OID::Bytea.new # bytea
        TYPE_MAP[16]  = OID::Boolean.new  # bool

        TYPE_MAP[700] = OID::Float.new # float4
        TYPE_MAP[701] = TYPE_MAP[700]  # float8

        TYPE_MAP[1114] = OID::Timestamp.new # timestamp
        TYPE_MAP[1082] = OID::Date.new # date
        TYPE_MAP[1083] = OID::Time.new # time

        TYPE_MAP[1009] = OID::Vector.new(',', TYPE_MAP[25]) # _text
        TYPE_MAP[1007] = OID::Vector.new(',', TYPE_MAP[23]) # _int4
      end
    end
  end
end

