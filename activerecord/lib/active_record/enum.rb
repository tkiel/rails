require 'active_support/core_ext/object/deep_dup'

module ActiveRecord
  # Declare an enum attribute where the values map to integers in the database,
  # but can be queried by name. Example:
  #
  #   class Conversation < ActiveRecord::Base
  #     enum status: [ :active, :archived ]
  #   end
  #
  #   # conversation.update! status: 0
  #   conversation.active!
  #   conversation.active? # => true
  #   conversation.status  # => "active"
  #
  #   # conversation.update! status: 1
  #   conversation.archived!
  #   conversation.archived? # => true
  #   conversation.status    # => "archived"
  #
  #   # conversation.update! status: 1
  #   conversation.status = "archived"
  #
  #   # conversation.update! status: nil
  #   conversation.status = nil
  #   conversation.status.nil? # => true
  #   conversation.status      # => nil
  #
  # Scopes based on the allowed values of the enum field will be provided
  # as well. With the above example:
  #
  #   Conversation.active
  #   Conversation.archived
  #
  # Of course, you can also query them directly if the scopes don't fit your
  # needs:
  #
  #   Conversation.where(status: [:active, :archived])
  #   Conversation.where.not(status: :active)
  #
  # You can set the default value from the database declaration, like:
  #
  #   create_table :conversations do |t|
  #     t.column :status, :integer, default: 0
  #   end
  #
  # Good practice is to let the first declared status be the default.
  #
  # Finally, it's also possible to explicitly map the relation between attribute and
  # database integer with a +Hash+:
  #
  #   class Conversation < ActiveRecord::Base
  #     enum status: { active: 0, archived: 1 }
  #   end
  #
  # Note that when an +Array+ is used, the implicit mapping from the values to database
  # integers is derived from the order the values appear in the array. In the example,
  # <tt>:active</tt> is mapped to +0+ as it's the first element, and <tt>:archived</tt>
  # is mapped to +1+. In general, the +i+-th element is mapped to <tt>i-1</tt> in the
  # database.
  #
  # Therefore, once a value is added to the enum array, its position in the array must
  # be maintained, and new values should only be added to the end of the array. To
  # remove unused values, the explicit +Hash+ syntax should be used.
  #
  # In rare circumstances you might need to access the mapping directly.
  # The mappings are exposed through a class method with the pluralized attribute
  # name, which return the mapping in a +HashWithIndifferentAccess+:
  #
  #   Conversation.statuses[:active]    # => 0
  #   Conversation.statuses["archived"] # => 1
  #
  # Use that class method when you need to know the ordinal value of an enum.
  # For example, you can use that when manually building SQL strings:
  #
  #   Conversation.where("status <> ?", Conversation.statuses[:archived])
  #
  # You can use <tt>:enum_prefix</tt>/<tt>:enum_suffix</tt> option then you need
  # to define multiple enums with same values. If option value is <tt>true</tt>,
  # the methods are prefixed/suffixed with the name of the enum.
  #
  #   class Invoice < ActiveRecord::Base
  #     enum verification: [:done, :fail], enum_prefix: true
  #   end
  #
  # It is also possible to supply a custom prefix.
  #
  #   class Invoice < ActiveRecord::Base
  #     enum verification: [:done, :fail], enum_prefix: :verification_status
  #   end
  #
  # Note that <tt>:enum_prefix</tt>/<tt>:enum_postfix</tt> are reserved keywords
  # and can not be used as an enum name.

  module Enum
    def self.extended(base) # :nodoc:
      base.class_attribute(:defined_enums)
      base.defined_enums = {}
    end

    def inherited(base) # :nodoc:
      base.defined_enums = defined_enums.deep_dup
      super
    end

    class EnumType < Type::Value
      def initialize(name, mapping)
        @name = name
        @mapping = mapping
      end

      def cast(value)
        return if value.blank?

        if mapping.has_key?(value)
          value.to_s
        elsif mapping.has_value?(value)
          mapping.key(value)
        else
          raise ArgumentError, "'#{value}' is not a valid #{name}"
        end
      end

      def deserialize(value)
        return if value.nil?
        mapping.key(value.to_i)
      end

      def serialize(value)
        mapping.fetch(value, value)
      end

      protected

      attr_reader :name, :mapping
    end

    def enum(definitions)
      klass = self
      enum_prefix = definitions.delete(:enum_prefix)
      enum_suffix = definitions.delete(:enum_suffix)
      definitions.each do |name, values|
        # statuses = { }
        enum_values = ActiveSupport::HashWithIndifferentAccess.new
        name        = name.to_sym

        # def self.statuses statuses end
        detect_enum_conflict!(name, name.to_s.pluralize, true)
        klass.singleton_class.send(:define_method, name.to_s.pluralize) { enum_values }

        detect_enum_conflict!(name, name)
        detect_enum_conflict!(name, "#{name}=")

        attribute name, EnumType.new(name, enum_values)

        _enum_methods_module.module_eval do
          pairs = values.respond_to?(:each_pair) ? values.each_pair : values.each_with_index
          pairs.each do |value, i|
            if enum_prefix == true
              prefix = "#{name}_"
            elsif enum_prefix
              prefix = "#{enum_prefix}_"
            end
            if enum_suffix == true
              suffix = "_#{name}"
            elsif enum_suffix
              suffix = "_#{enum_suffix}"
            end

            value_method_name = "#{prefix}#{value}#{suffix}"
            enum_values[value] = i

            # def active?() status == 0 end
            klass.send(:detect_enum_conflict!, name, "#{value_method_name}?")
            define_method("#{value_method_name}?") { self[name] == value.to_s }

            # def active!() update! status: :active end
            klass.send(:detect_enum_conflict!, name, "#{value_method_name}!")
            define_method("#{value_method_name}!") { update! name => value }

            # scope :active, -> { where status: 0 }
            klass.send(:detect_enum_conflict!, name, value_method_name, true)
            klass.scope value_method_name, -> { klass.where name => value }
          end
        end
        defined_enums[name.to_s] = enum_values
      end
    end

    private
      def _enum_methods_module
        @_enum_methods_module ||= begin
          mod = Module.new
          include mod
          mod
        end
      end

      ENUM_CONFLICT_MESSAGE = \
        "You tried to define an enum named \"%{enum}\" on the model \"%{klass}\", but " \
        "this will generate a %{type} method \"%{method}\", which is already defined " \
        "by %{source}."

      def detect_enum_conflict!(enum_name, method_name, klass_method = false)
        if klass_method && dangerous_class_method?(method_name)
          raise ArgumentError, ENUM_CONFLICT_MESSAGE % {
            enum: enum_name,
            klass: self.name,
            type: 'class',
            method: method_name,
            source: 'Active Record'
          }
        elsif !klass_method && dangerous_attribute_method?(method_name)
          raise ArgumentError, ENUM_CONFLICT_MESSAGE % {
            enum: enum_name,
            klass: self.name,
            type: 'instance',
            method: method_name,
            source: 'Active Record'
          }
        elsif !klass_method && method_defined_within?(method_name, _enum_methods_module, Module)
          raise ArgumentError, ENUM_CONFLICT_MESSAGE % {
            enum: enum_name,
            klass: self.name,
            type: 'instance',
            method: method_name,
            source: 'another enum'
          }
        end
      end
  end
end
