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
    end
  end

  class LazyAttributeHash # :nodoc:
    delegate :select, :transform_values, :each_key, to: :materialize

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
      delegate_hash[key] || assign_default_value(key)
    end

    def []=(key, value)
      if frozen?
        raise RuntimeError, "Can't modify frozen hash"
      end
      delegate_hash[key] = value
    end

    def initialize_dup(_)
      @delegate_hash = delegate_hash.transform_values(&:dup)
      super
    end

    protected

    attr_reader :types, :values, :additional_types, :delegate_hash

    private

    def assign_default_value(name)
      type = additional_types.fetch(name, types[name])
      value_present = true
      value = values.fetch(name) { value_present = false }

      if value_present
        delegate_hash[name] = Attribute.from_database(name, value, type)
      elsif types.key?(name)
        delegate_hash[name] = Attribute.uninitialized(name, type)
      end
    end

    def materialize
      unless @materialized
        values.each_key { |key| self[key] }
        types.each_key { |key| self[key] }
        unless frozen?
          @materialized = true
        end
      end
      delegate_hash
    end
  end
end
