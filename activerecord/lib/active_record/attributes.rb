module ActiveRecord
  module Attributes
    extend ActiveSupport::Concern

    Type = ActiveRecord::Type

    included do
      class_attribute :attributes_to_define_after_schema_loads, instance_accessor: false # :internal:
      self.attributes_to_define_after_schema_loads = {}
    end

    module ClassMethods
      # Defines an attribute with a type on this model. It will override the
      # type of existing attributes if needed. This allows control over how
      # values are converted to and from SQL when assigned to a model. It also
      # changes the behavior of values passed to
      # +ActiveRecord::Relation::QueryMethods#where+. This will let you use
      # your domain objects across much of Active Record, without having to
      # rely on implementation details or monkey patching.
      #
      # +name+ The name of the methods to define attribute methods for, and the
      # column which this will persist to.
      #
      # +cast_type+ A type object that contains information about how to type cast the value.
      # See the examples section for more information.
      #
      # ==== Options
      # The following options are accepted:
      #
      # +default+ The default value to use when no value is provided. If this option
      # is not passed, the previous default value (if any) will be used.
      # Otherwise, the default will be +nil+.
      #
      # +array+ (PG only) specifies that the type should be an array (see the examples below)
      #
      # +range+ (PG only) specifies that the type should be a range (see the examples below)
      #
      # ==== Examples
      #
      # The type detected by Active Record can be overridden.
      #
      #   # db/schema.rb
      #   create_table :store_listings, force: true do |t|
      #     t.decimal :price_in_cents
      #   end
      #
      #   # app/models/store_listing.rb
      #   class StoreListing < ActiveRecord::Base
      #   end
      #
      #   store_listing = StoreListing.new(price_in_cents: '10.1')
      #
      #   # before
      #   store_listing.price_in_cents # => BigDecimal.new(10.1)
      #
      #   class StoreListing < ActiveRecord::Base
      #     attribute :price_in_cents, :integer
      #   end
      #
      #   # after
      #   store_listing.price_in_cents # => 10
      #
      # Attributes do not need to be backed by a database column.
      #
      #   class MyModel < ActiveRecord::Base
      #     attribute :my_string, :string
      #     attribute :my_int_array, :integer, array: true
      #     attribute :my_float_range, :float, range: true
      #   end
      #
      #   model = MyModel.new(
      #     my_string: "string",
      #     my_int_array: ["1", "2", "3"],
      #     my_float_range: "[1,3.5]",
      #   )
      #   model.attributes
      #   # =>
      #     {
      #       my_string: "string",
      #       my_int_array: [1, 2, 3],
      #       my_float_range: 1.0..3.5
      #     }
      #
      # ==== Creating Custom Types
      #
      # Users may also define their own custom types, as long as they respond
      # to the methods defined on the value type. The +type_cast+ method on
      # your type object will be called with values both from the database, and
      # from your controllers. See +ActiveRecord::Attributes::Type::Value+ for
      # the expected API. It is recommended that your type objects inherit from
      # an existing type, or the base value type.
      #
      #   class MoneyType < ActiveRecord::Type::Integer
      #     def type_cast(value)
      #       if value.include?('$')
      #         price_in_dollars = value.gsub(/\$/, '').to_f
      #         price_in_dollars * 100
      #       else
      #         value.to_i
      #       end
      #     end
      #   end
      #
      #   class StoreListing < ActiveRecord::Base
      #     attribute :price_in_cents, MoneyType.new
      #   end
      #
      #   store_listing = StoreListing.new(price_in_cents: '$10.00')
      #   store_listing.price_in_cents # => 1000
      #
      # For more details on creating custom types, see the documentation for
      # +ActiveRecord::Type::Value+
      #
      # ==== Querying
      #
      # When +ActiveRecord::Relation::QueryMethods#where+ is called, it will
      # use the type defined by the model class to convert the value to SQL,
      # calling +type_cast_for_database+ on your type object. For example:
      #
      #   class Money < Struct.new(:amount, :currency)
      #   end
      #
      #   class MoneyType < Type::Value
      #     def initialize(currency_converter)
      #       @currency_converter = currency_converter
      #     end
      #
      #     # value will be the result of +type_cast_from_database+ or
      #     # +type_cast_from_user+. Assumed to be in instance of +Money+ in
      #     # this case.
      #     def type_cast_for_database(value)
      #       value_in_bitcoins = currency_converter.convert_to_bitcoins(value)
      #       value_in_bitcoins.amount
      #     end
      #   end
      #
      #   class Product < ActiveRecord::Base
      #     currency_converter = ConversionRatesFromTheInternet.new
      #     attribute :price_in_bitcoins, MoneyType.new(currency_converter)
      #   end
      #
      #   Product.where(price_in_bitcoins: Money.new(5, "USD"))
      #   # => SELECT * FROM products WHERE price_in_bitcoins = 0.02230
      #
      #   Product.where(price_in_bitcoins: Money.new(5, "GBP"))
      #   # => SELECT * FROM products WHERE price_in_bitcoins = 0.03412
      #
      # ==== Dirty Tracking
      #
      # The type of an attribute is given the opportunity to change how dirty
      # tracking is performed. The methods +changed?+ and +changed_in_place?+
      # will be called from +ActiveRecord::AttributeMethods::Dirty+. See the
      # documentation for those methods in +ActiveRecord::Type::Value+ for more
      # details.
      def attribute(name, cast_type, **options)
        name = name.to_s
        reload_schema_from_cache

        self.attributes_to_define_after_schema_loads =
          attributes_to_define_after_schema_loads.merge(
            name => [cast_type, options]
          )
      end

      # This is the low level API which sits beneath +attribute+. It only
      # accepts type objects, and will do its work immediately instead of
      # waiting for the schema to load. Automatic schema detection and
      # +attribute+ both call this under the hood. While this method is
      # provided so it can be used by plugin authors, application code should
      # probably use +attribute+.
      #
      # +name+ The name of the attribute being defined. Expected to be a +String+.
      #
      # +cast_type+ The type object to use for this attribute
      #
      # +default+ The default value to use when no value is provided. If this option
      # is not passed, the previous default value (if any) will be used.
      # Otherwise, the default will be +nil+.
      #
      # +user_provided_default+ Whether the default value should be cast using
      # +type_cast_from_user+ or +type_cast_from_database+
      def define_attribute(
        name,
        cast_type,
        default: NO_DEFAULT_PROVIDED,
        user_provided_default: true
      )
        attribute_types[name] = cast_type
        define_default_attribute(name, default, cast_type, from_user: user_provided_default)
      end

      def load_schema! # :nodoc:
        super
        attributes_to_define_after_schema_loads.each do |name, (type, options)|
          if type.is_a?(Symbol)
            type = connection.type_for_attribute_options(type, **options.except(:default))
          end

          define_attribute(name, type, **options.slice(:default))
        end
      end

      private

      NO_DEFAULT_PROVIDED = Object.new # :nodoc:
      private_constant :NO_DEFAULT_PROVIDED

      def define_default_attribute(name, value, type, from_user:)
        if value == NO_DEFAULT_PROVIDED
          default_attribute = _default_attributes[name].with_type(type)
        elsif from_user
          default_attribute = Attribute.from_user(name, value, type)
        else
          default_attribute = Attribute.from_database(name, value, type)
        end
        _default_attributes[name] = default_attribute
      end
    end
  end
end
