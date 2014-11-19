module ActiveRecord
  module Type
    class HashLookupTypeMap < TypeMap # :nodoc:
      delegate :key?, to: :@mapping

      def fetch(type, *args, &block)
        @mapping.fetch(type, block).call(type, *args)
      end

      def alias_type(type, alias_type)
        register_type(type) { |_, *args| lookup(alias_type, *args) }
      end
    end
  end
end
