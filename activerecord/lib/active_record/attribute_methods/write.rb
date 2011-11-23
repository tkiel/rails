module ActiveRecord
  module AttributeMethods
    module Write
      extend ActiveSupport::Concern

      included do
        attribute_method_suffix "="
      end

      module ClassMethods
        protected
          def define_method_attribute=(attr_name)
            if attr_name =~ ActiveModel::AttributeMethods::NAME_COMPILABLE_REGEXP
              generated_attribute_methods.module_eval("def #{attr_name}=(new_value); write_attribute('#{attr_name}', new_value); end", __FILE__, __LINE__)
            else
              generated_attribute_methods.send(:define_method, "#{attr_name}=") do |new_value|
                write_attribute(attr_name, new_value)
              end
            end

            if attr_name == primary_key && attr_name != "id"
              generated_attribute_methods.module_eval("alias :id= :'#{primary_key}='")
            end
          end
      end

      # Updates the attribute identified by <tt>attr_name</tt> with the specified +value+. Empty strings
      # for fixnum and float columns are turned into +nil+.
      def write_attribute(attr_name, value)
        attr_name = attr_name.to_s
        attr_name = self.class.primary_key if attr_name == 'id' && self.class.primary_key
        @attributes_cache.delete(attr_name)
        column = column_for_attribute(attr_name)

        if column && column.number?
          @attributes[attr_name] = convert_number_column_value(value)
        elsif column || @attributes.has_key?(attr_name)
          @attributes[attr_name] = value
        else
          raise ActiveModel::MissingAttributeError, "can't write unknown attribute `#{attr_name}'"
        end
      end
      alias_method :raw_write_attribute, :write_attribute

      private
        # Handle *= for method_missing.
        def attribute=(attribute_name, value)
          write_attribute(attribute_name, value)
        end
    end
  end
end
