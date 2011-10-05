module ActiveRecord
  module AttributeMethods
    module Read
      extend ActiveSupport::Concern

      ATTRIBUTE_TYPES_CACHED_BY_DEFAULT = [:datetime, :timestamp, :time, :date]

      included do
        cattr_accessor :attribute_types_cached_by_default, :instance_writer => false
        self.attribute_types_cached_by_default = ATTRIBUTE_TYPES_CACHED_BY_DEFAULT

        # Undefine id so it can be used as an attribute name
        undef_method(:id) if method_defined?(:id)
      end

      module ClassMethods
        # +cache_attributes+ allows you to declare which converted attribute values should
        # be cached. Usually caching only pays off for attributes with expensive conversion
        # methods, like time related columns (e.g. +created_at+, +updated_at+).
        def cache_attributes(*attribute_names)
          cached_attributes.merge attribute_names.map { |attr| attr.to_s }
        end

        # Returns the attributes which are cached. By default time related columns
        # with datatype <tt>:datetime, :timestamp, :time, :date</tt> are cached.
        def cached_attributes
          @cached_attributes ||= columns.select { |c| cacheable_column?(c) }.map { |col| col.name }.to_set
        end

        # Returns +true+ if the provided attribute is being cached.
        def cache_attribute?(attr_name)
          cached_attributes.include?(attr_name)
        end

        protected
          def define_method_attribute(attr_name)
            if serialized_attributes.include?(attr_name)
              define_read_method_for_serialized_attribute(attr_name)
            else
              define_read_method(attr_name, attr_name, columns_hash[attr_name])
            end

            if primary_key? && attr_name == primary_key && attr_name != "id"
              define_read_method('id', attr_name, columns_hash[attr_name])
            end
          end

        private
          def cacheable_column?(column)
            serialized_attributes.include?(column.name) || attribute_types_cached_by_default.include?(column.type)
          end

          # Define read method for serialized attribute.
          def define_read_method_for_serialized_attribute(attr_name)
            access_code = "@attributes_cache['#{attr_name}'] ||= @attributes['#{attr_name}']"
            generated_attribute_methods.module_eval("def _#{attr_name}; #{access_code}; end; alias #{attr_name} _#{attr_name}", __FILE__, __LINE__)
          end

          # Define an attribute reader method. Cope with nil column.
          # method_name is the same as attr_name except when a non-standard primary key is used,
          # we still define #id as an accessor for the key
          def define_read_method(method_name, attr_name, column)
            cast_code = column.type_cast_code('v')
            access_code = "(v=@attributes['#{attr_name}']) && #{cast_code}"

            unless primary_key? && attr_name.to_s == primary_key.to_s
              access_code.insert(0, "missing_attribute('#{attr_name}', caller) unless @attributes.has_key?('#{attr_name}'); ")
            end

            if cache_attribute?(attr_name)
              access_code = "@attributes_cache['#{attr_name}'] ||= (#{access_code})"
            end

            # Where possible, generate the method by evalling a string, as this will result in
            # faster accesses because it avoids the block eval and then string eval incurred
            # by the second branch.
            #
            # The second, slower, branch is necessary to support instances where the database
            # returns columns with extra stuff in (like 'my_column(omg)').
            if method_name =~ ActiveModel::AttributeMethods::COMPILABLE_REGEXP
              generated_attribute_methods.module_eval <<-STR, __FILE__, __LINE__
                def _#{method_name}
                  #{access_code}
                end

                alias #{method_name} _#{method_name}
              STR
            else
              generated_attribute_methods.module_eval do
                define_method("_#{method_name}") { eval(access_code) }
                alias_method(method_name, "_#{method_name}")
              end
            end
          end
      end

      # Returns the value of the attribute identified by <tt>attr_name</tt> after it has been typecast (for example,
      # "2004-12-12" in a data column is cast to a date object, like Date.new(2004, 12, 12)).
      def read_attribute(attr_name)
        method = "_#{attr_name}"
        if respond_to? method
          send method if @attributes.has_key?(attr_name.to_s)
        else
          _read_attribute attr_name
        end
      end

      def _read_attribute(attr_name)
        attr_name = attr_name.to_s
        attr_name = self.class.primary_key? && self.class.primary_key if attr_name == 'id'
        value = @attributes[attr_name]
        unless value.nil?
          if column = column_for_attribute(attr_name)
            if unserializable_attribute?(attr_name, column)
              unserialize_attribute(attr_name)
            else
              column.type_cast(value)
            end
          else
            value
          end
        end
      end

      # Returns true if the attribute is of a text column and marked for serialization.
      def unserializable_attribute?(attr_name, column)
        column.text? && self.class.serialized_attributes.include?(attr_name)
      end

      # Returns the unserialized object of the attribute.
      def unserialize_attribute(attr_name)
        coder = self.class.serialized_attributes[attr_name]
        unserialized_object = coder.load(@attributes[attr_name])

        @attributes.frozen? ? unserialized_object : @attributes[attr_name] = unserialized_object
      end

      private
        def attribute(attribute_name)
          read_attribute(attribute_name)
        end
    end
  end
end
