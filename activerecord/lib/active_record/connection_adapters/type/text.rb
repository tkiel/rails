require 'active_record/connection_adapters/type/string'

module ActiveRecord
  module ConnectionAdapters
    module Type
      class Text < String
        def type
          :text
        end
      end
    end
  end
end
