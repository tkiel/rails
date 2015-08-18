require 'active_record/connection_adapters/postgresql/oid/array'
require 'active_record/connection_adapters/postgresql/oid/bit'
require 'active_record/connection_adapters/postgresql/oid/bit_varying'
require 'active_record/connection_adapters/postgresql/oid/bytea'
require 'active_record/connection_adapters/postgresql/oid/cidr'
require 'active_record/connection_adapters/postgresql/oid/date_time'
require 'active_record/connection_adapters/postgresql/oid/decimal'
require 'active_record/connection_adapters/postgresql/oid/enum'
require 'active_record/connection_adapters/postgresql/oid/hstore'
require 'active_record/connection_adapters/postgresql/oid/inet'
require 'active_record/connection_adapters/postgresql/oid/jsonb'
require 'active_record/connection_adapters/postgresql/oid/money'
require 'active_record/connection_adapters/postgresql/oid/point'
require 'active_record/connection_adapters/postgresql/oid/rails_5_1_point'
require 'active_record/connection_adapters/postgresql/oid/range'
require 'active_record/connection_adapters/postgresql/oid/specialized_string'
require 'active_record/connection_adapters/postgresql/oid/uuid'
require 'active_record/connection_adapters/postgresql/oid/vector'
require 'active_record/connection_adapters/postgresql/oid/xml'

require 'active_record/connection_adapters/postgresql/oid/type_map_initializer'

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module OID # :nodoc:
      end
    end
  end
end
