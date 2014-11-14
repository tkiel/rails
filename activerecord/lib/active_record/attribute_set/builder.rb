module ActiveRecord
  class AttributeSet # :nodoc:
    class Builder # :nodoc:
      attr_reader :types, :always_initialized

      def initialize(types, always_initialized = nil)
        @types = types
        @always_initialized = always_initialized
      end

      def build_from_database(values = {}, additional_types = {})
        if always_initialized && !values.key?(always_initialized)
          values[always_initialized] = nil
        end

        attributes = LazyAttributeHash.new(types, values, additional_types)
        AttributeSet.new(attributes)
      end

      private
    end
  end

  class LazyAttributeHash
    delegate :select, :transform_values, to: :materialize
    delegate :[]=, :freeze, to: :delegate_hash

    def initialize(types, values, additional_types)
      @types = types
      @values = values
      @additional_types = additional_types
      @materialized = false
      @delegate_hash = {}
    end

    def key?(key)
      delegate_hash.key?(key) || values.key?(key) || types.key?(key)
    end

    def [](key)
      if delegate_hash.key?(key)
        delegate_hash[key]
      else
        assign_default_value(key)
      end
    end

    def initialized_keys
      delegate_hash.keys | values.keys
    end

    def initialize_dup(_)
      @delegate_hash = delegate_hash.transform_values(&:dup)
      super
    end

    def initialize_clone(_)
      @delegate_hash = delegate_hash.clone
      super
    end

    protected

    attr_reader :types, :values, :additional_types, :delegate_hash

    private

    def assign_default_value(name)
      type = additional_types.fetch(name, types[name])

      if values.key?(name)
        delegate_hash[name] = Attribute.from_database(name, values[name], type)
      elsif types.key?(name)
        delegate_hash[name] = Attribute.uninitialized(name, type)
      end
    end

    def materialize
      unless @materialized
        values.each_key { |key| self[key] }
        types.each_key { |key| self[key] }
        @materialized = true
      end
      delegate_hash
    end
  end
end
