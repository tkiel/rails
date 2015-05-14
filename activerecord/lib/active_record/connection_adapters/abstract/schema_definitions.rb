require 'date'
require 'bigdecimal'
require 'bigdecimal/util'

module ActiveRecord
  module ConnectionAdapters #:nodoc:
    # Abstract representation of an index definition on a table. Instances of
    # this type are typically created and returned by methods in database
    # adapters. e.g. ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter#indexes
    class IndexDefinition < Struct.new(:table, :name, :unique, :columns, :lengths, :orders, :where, :type, :using) #:nodoc:
    end

    # Abstract representation of a column definition. Instances of this type
    # are typically created by methods in TableDefinition, and added to the
    # +columns+ attribute of said TableDefinition object, in order to be used
    # for generating a number of table creation or table changing SQL statements.
    class ColumnDefinition < Struct.new(:name, :type, :limit, :precision, :scale, :default, :null, :first, :after, :auto_increment, :primary_key, :collation, :sql_type) #:nodoc:

      def primary_key?
        primary_key || type.to_sym == :primary_key
      end
    end

    class AddColumnDefinition < Struct.new(:column) # :nodoc:
    end

    class ChangeColumnDefinition < Struct.new(:column, :name) #:nodoc:
    end

    class ForeignKeyDefinition < Struct.new(:from_table, :to_table, :options) #:nodoc:
      def name
        options[:name]
      end

      def column
        options[:column]
      end

      def primary_key
        options[:primary_key] || default_primary_key
      end

      def on_delete
        options[:on_delete]
      end

      def on_update
        options[:on_update]
      end

      def custom_primary_key?
        options[:primary_key] != default_primary_key
      end

      def defined_for?(options_or_to_table = {})
        if options_or_to_table.is_a?(Hash)
          options_or_to_table.all? {|key, value| options[key].to_s == value.to_s }
        else
          to_table == options_or_to_table.to_s
        end
      end

      private
      def default_primary_key
        "id"
      end
    end

    class ReferenceDefinition # :nodoc:
      def initialize(
        name,
        polymorphic: false,
        index: false,
        foreign_key: false,
        type: :integer,
        **options
      )
        @name = name
        @polymorphic = polymorphic
        @index = index
        @foreign_key = foreign_key
        @type = type
        @options = options

        if polymorphic && foreign_key
          raise ArgumentError, "Cannot add a foreign key to a polymorphic relation"
        end
      end

      def add_to(table)
        columns.each do |column_options|
          table.column(*column_options)
        end

        if index
          table.index(column_names, index_options)
        end

        if foreign_key
          table.foreign_key(foreign_table_name, foreign_key_options)
        end
      end

      protected

      attr_reader :name, :polymorphic, :index, :foreign_key, :type, :options

      private

      def as_options(value, default = {})
        if value.is_a?(Hash)
          value
        else
          default
        end
      end

      def polymorphic_options
        as_options(polymorphic, options)
      end

      def index_options
        as_options(index)
      end

      def foreign_key_options
        as_options(foreign_key)
      end

      def columns
        result = [["#{name}_id", type, options]]
        if polymorphic
          result.unshift(["#{name}_type", :string, polymorphic_options])
        end
        result
      end

      def column_names
        columns.map(&:first)
      end

      def foreign_table_name
        Base.pluralize_table_names ? name.to_s.pluralize : name
      end
    end

    module ColumnMethods
      # Appends a primary key definition to the table definition.
      # Can be called multiple times, but this is probably not a good idea.
      def primary_key(name, type = :primary_key, **options)
        column(name, type, options.merge(primary_key: true))
      end

      # Appends a column or columns of a specified type.
      #
      #  t.string(:goat)
      #  t.string(:goat, :sheep)
      #
      # See TableDefinition#column
      [
        :bigint,
        :binary,
        :boolean,
        :date,
        :datetime,
        :decimal,
        :float,
        :integer,
        :string,
        :text,
        :time,
        :timestamp,
      ].each do |column_type|
        module_eval <<-CODE, __FILE__, __LINE__ + 1
          def #{column_type}(*args, **options)
            args.each { |name| column(name, :#{column_type}, options) }
          end
        CODE
      end
    end

    # Represents the schema of an SQL table in an abstract way. This class
    # provides methods for manipulating the schema representation.
    #
    # Inside migration files, the +t+ object in +create_table+
    # is actually of this type:
    #
    #   class SomeMigration < ActiveRecord::Migration
    #     def up
    #       create_table :foo do |t|
    #         puts t.class  # => "ActiveRecord::ConnectionAdapters::TableDefinition"
    #       end
    #     end
    #
    #     def down
    #       ...
    #     end
    #   end
    #
    # The table definitions
    # The Columns are stored as a ColumnDefinition in the +columns+ attribute.
    class TableDefinition
      include ColumnMethods

      # An array of ColumnDefinition objects, representing the column changes
      # that have been defined.
      attr_accessor :indexes
      attr_reader :name, :temporary, :options, :as, :foreign_keys

      def initialize(types, name, temporary, options, as = nil)
        @columns_hash = {}
        @indexes = {}
        @foreign_keys = {}
        @native = types
        @temporary = temporary
        @options = options
        @as = as
        @name = name
      end

      def columns; @columns_hash.values; end

      # Returns a ColumnDefinition for the column with name +name+.
      def [](name)
        @columns_hash[name.to_s]
      end

      # Instantiates a new column for the table.
      # The +type+ parameter is normally one of the migrations native types,
      # which is one of the following:
      # <tt>:primary_key</tt>, <tt>:string</tt>, <tt>:text</tt>,
      # <tt>:integer</tt>, <tt>:bigint</tt>, <tt>:float</tt>, <tt>:decimal</tt>,
      # <tt>:datetime</tt>, <tt>:time</tt>, <tt>:date</tt>,
      # <tt>:binary</tt>, <tt>:boolean</tt>.
      #
      # You may use a type not in this list as long as it is supported by your
      # database (for example, "polygon" in MySQL), but this will not be database
      # agnostic and should usually be avoided.
      #
      # Available options are (none of these exists by default):
      # * <tt>:limit</tt> -
      #   Requests a maximum column length. This is number of characters for <tt>:string</tt> and
      #   <tt>:text</tt> columns and number of bytes for <tt>:binary</tt> and <tt>:integer</tt> columns.
      # * <tt>:default</tt> -
      #   The column's default value. Use nil for NULL.
      # * <tt>:null</tt> -
      #   Allows or disallows +NULL+ values in the column. This option could
      #   have been named <tt>:null_allowed</tt>.
      # * <tt>:precision</tt> -
      #   Specifies the precision for a <tt>:decimal</tt> column.
      # * <tt>:scale</tt> -
      #   Specifies the scale for a <tt>:decimal</tt> column.
      # * <tt>:index</tt> -
      #   Create an index for the column. Can be either <tt>true</tt> or an options hash.
      #
      # Note: The precision is the total number of significant digits
      # and the scale is the number of digits that can be stored following
      # the decimal point. For example, the number 123.45 has a precision of 5
      # and a scale of 2. A decimal with a precision of 5 and a scale of 2 can
      # range from -999.99 to 999.99.
      #
      # Please be aware of different RDBMS implementations behavior with
      # <tt>:decimal</tt> columns:
      # * The SQL standard says the default scale should be 0, <tt>:scale</tt> <=
      #   <tt>:precision</tt>, and makes no comments about the requirements of
      #   <tt>:precision</tt>.
      # * MySQL: <tt>:precision</tt> [1..63], <tt>:scale</tt> [0..30].
      #   Default is (10,0).
      # * PostgreSQL: <tt>:precision</tt> [1..infinity],
      #   <tt>:scale</tt> [0..infinity]. No default.
      # * SQLite2: Any <tt>:precision</tt> and <tt>:scale</tt> may be used.
      #   Internal storage as strings. No default.
      # * SQLite3: No restrictions on <tt>:precision</tt> and <tt>:scale</tt>,
      #   but the maximum supported <tt>:precision</tt> is 16. No default.
      # * Oracle: <tt>:precision</tt> [1..38], <tt>:scale</tt> [-84..127].
      #   Default is (38,0).
      # * DB2: <tt>:precision</tt> [1..63], <tt>:scale</tt> [0..62].
      #   Default unknown.
      # * SqlServer?: <tt>:precision</tt> [1..38], <tt>:scale</tt> [0..38].
      #   Default (38,0).
      #
      # This method returns <tt>self</tt>.
      #
      # == Examples
      #  # Assuming +td+ is an instance of TableDefinition
      #  td.column(:granted, :boolean)
      #  # granted BOOLEAN
      #
      #  td.column(:picture, :binary, limit: 2.megabytes)
      #  # => picture BLOB(2097152)
      #
      #  td.column(:sales_stage, :string, limit: 20, default: 'new', null: false)
      #  # => sales_stage VARCHAR(20) DEFAULT 'new' NOT NULL
      #
      #  td.column(:bill_gates_money, :decimal, precision: 15, scale: 2)
      #  # => bill_gates_money DECIMAL(15,2)
      #
      #  td.column(:sensor_reading, :decimal, precision: 30, scale: 20)
      #  # => sensor_reading DECIMAL(30,20)
      #
      #  # While <tt>:scale</tt> defaults to zero on most databases, it
      #  # probably wouldn't hurt to include it.
      #  td.column(:huge_integer, :decimal, precision: 30)
      #  # => huge_integer DECIMAL(30)
      #
      #  # Defines a column with a database-specific type.
      #  td.column(:foo, 'polygon')
      #  # => foo polygon
      #
      # == Short-hand examples
      #
      # Instead of calling +column+ directly, you can also work with the short-hand definitions for the default types.
      # They use the type as the method name instead of as a parameter and allow for multiple columns to be defined
      # in a single statement.
      #
      # What can be written like this with the regular calls to column:
      #
      #   create_table :products do |t|
      #     t.column :shop_id,     :integer
      #     t.column :creator_id,  :integer
      #     t.column :item_number, :string
      #     t.column :name,        :string, default: "Untitled"
      #     t.column :value,       :string, default: "Untitled"
      #     t.column :created_at,  :datetime
      #     t.column :updated_at,  :datetime
      #   end
      #   add_index :products, :item_number
      #
      # can also be written as follows using the short-hand:
      #
      #   create_table :products do |t|
      #     t.integer :shop_id, :creator_id
      #     t.string  :item_number, index: true
      #     t.string  :name, :value, default: "Untitled"
      #     t.timestamps null: false
      #   end
      #
      # There's a short-hand method for each of the type values declared at the top. And then there's
      # TableDefinition#timestamps that'll add +created_at+ and +updated_at+ as datetimes.
      #
      # TableDefinition#references will add an appropriately-named _id column, plus a corresponding _type
      # column if the <tt>:polymorphic</tt> option is supplied. If <tt>:polymorphic</tt> is a hash of
      # options, these will be used when creating the <tt>_type</tt> column. The <tt>:index</tt> option
      # will also create an index, similar to calling <tt>add_index</tt>. So what can be written like this:
      #
      #   create_table :taggings do |t|
      #     t.integer :tag_id, :tagger_id, :taggable_id
      #     t.string  :tagger_type
      #     t.string  :taggable_type, default: 'Photo'
      #   end
      #   add_index :taggings, :tag_id, name: 'index_taggings_on_tag_id'
      #   add_index :taggings, [:tagger_id, :tagger_type]
      #
      # Can also be written as follows using references:
      #
      #   create_table :taggings do |t|
      #     t.references :tag, index: { name: 'index_taggings_on_tag_id' }
      #     t.references :tagger, polymorphic: true, index: true
      #     t.references :taggable, polymorphic: { default: 'Photo' }
      #   end
      def column(name, type, options = {})
        name = name.to_s
        type = type.to_sym
        options = options.dup

        if @columns_hash[name] && @columns_hash[name].primary_key?
          raise ArgumentError, "you can't redefine the primary key column '#{name}'. To define a custom primary key, pass { id: false } to create_table."
        end

        index_options = options.delete(:index)
        index(name, index_options.is_a?(Hash) ? index_options : {}) if index_options
        @columns_hash[name] = new_column_definition(name, type, options)
        self
      end

      def remove_column(name)
        @columns_hash.delete name.to_s
      end

      # Adds index options to the indexes hash, keyed by column name
      # This is primarily used to track indexes that need to be created after the table
      #
      #   index(:account_id, name: 'index_projects_on_account_id')
      def index(column_name, options = {})
        indexes[column_name] = options
      end

      def foreign_key(table_name, options = {}) # :nodoc:
        foreign_keys[table_name] = options
      end

      # Appends <tt>:datetime</tt> columns <tt>:created_at</tt> and
      # <tt>:updated_at</tt> to the table. See SchemaStatements#add_timestamps
      #
      #   t.timestamps null: false
      def timestamps(*args)
        options = args.extract_options!

        options[:null] = false if options[:null].nil?

        column(:created_at, :datetime, options)
        column(:updated_at, :datetime, options)
      end

      # Adds a reference. Optionally adds a +type+ column, if the
      # +:polymorphic+ option is provided. +references+ and +belongs_to+
      # are interchangeable. The reference column will be an +integer+ by default,
      # the +:type+ option can be used to specify a different type. A foreign
      # key will be created if the +:foreign_key+ option is passed.
      #
      #  t.references(:user)
      #  t.references(:user, type: "string")
      #  t.belongs_to(:supplier, polymorphic: true)
      #
      # See SchemaStatements#add_reference
      def references(*args, **options)
        args.each do |col|
          ReferenceDefinition.new(col, **options).add_to(self)
        end
      end
      alias :belongs_to :references

      def new_column_definition(name, type, options) # :nodoc:
        type = aliased_types(type.to_s, type)
        column = create_column_definition name, type
        limit = options.fetch(:limit) do
          native[type][:limit] if native[type].is_a?(Hash)
        end

        column.limit       = limit
        column.precision   = options[:precision]
        column.scale       = options[:scale]
        column.default     = options[:default]
        column.null        = options[:null]
        column.first       = options[:first]
        column.after       = options[:after]
        column.auto_increment = options[:auto_increment]
        column.primary_key = type == :primary_key || options[:primary_key]
        column.collation   = options[:collation]
        column
      end

      private
      def create_column_definition(name, type)
        ColumnDefinition.new name, type
      end

      def native
        @native
      end

      def aliased_types(name, fallback)
        'timestamp' == name ? :datetime : fallback
      end
    end

    class AlterTable # :nodoc:
      attr_reader :adds
      attr_reader :foreign_key_adds
      attr_reader :foreign_key_drops

      def initialize(td)
        @td   = td
        @adds = []
        @foreign_key_adds = []
        @foreign_key_drops = []
      end

      def name; @td.name; end

      def add_foreign_key(to_table, options)
        @foreign_key_adds << ForeignKeyDefinition.new(name, to_table, options)
      end

      def drop_foreign_key(name)
        @foreign_key_drops << name
      end

      def add_column(name, type, options)
        name = name.to_s
        type = type.to_sym
        @adds << AddColumnDefinition.new(@td.new_column_definition(name, type, options))
      end
    end

    # Represents an SQL table in an abstract way for updating a table.
    # Also see TableDefinition and SchemaStatements#create_table
    #
    # Available transformations are:
    #
    #   change_table :table do |t|
    #     t.primary_key
    #     t.column
    #     t.index
    #     t.rename_index
    #     t.timestamps
    #     t.change
    #     t.change_default
    #     t.rename
    #     t.references
    #     t.belongs_to
    #     t.string
    #     t.text
    #     t.integer
    #     t.bigint
    #     t.float
    #     t.decimal
    #     t.datetime
    #     t.timestamp
    #     t.time
    #     t.date
    #     t.binary
    #     t.boolean
    #     t.remove
    #     t.remove_references
    #     t.remove_belongs_to
    #     t.remove_index
    #     t.remove_timestamps
    #   end
    #
    class Table
      include ColumnMethods

      attr_reader :name

      def initialize(table_name, base)
        @name = table_name
        @base = base
      end

      # Adds a new column to the named table.
      #
      #  t.column(:name, :string)
      #
      # See TableDefinition#column for details of the options you can use.
      def column(column_name, type, options = {})
        @base.add_column(name, column_name, type, options)
      end

      # Checks to see if a column exists.
      #
      # t.string(:name) unless t.column_exists?(:name, :string)
      #
      # See SchemaStatements#column_exists?
      def column_exists?(column_name, type = nil, options = {})
        @base.column_exists?(name, column_name, type, options)
      end

      # Adds a new index to the table. +column_name+ can be a single Symbol, or
      # an Array of Symbols.
      #
      #  t.index(:name)
      #  t.index([:branch_id, :party_id], unique: true)
      #  t.index([:branch_id, :party_id], unique: true, name: 'by_branch_party')
      #
      # See SchemaStatements#add_index for details of the options you can use.
      def index(column_name, options = {})
        @base.add_index(name, column_name, options)
      end

      # Checks to see if an index exists.
      #
      # unless t.index_exists?(:branch_id)
      #   t.index(:branch_id)
      # end
      #
      # See SchemaStatements#index_exists?
      def index_exists?(column_name, options = {})
        @base.index_exists?(name, column_name, options)
      end

      # Renames the given index on the table.
      #
      #  t.rename_index(:user_id, :account_id)
      #
      # See SchemaStatements#rename_index
      def rename_index(index_name, new_index_name)
        @base.rename_index(name, index_name, new_index_name)
      end

      # Adds timestamps (+created_at+ and +updated_at+) columns to the table.
      #
      #  t.timestamps(null: false)
      #
      # See SchemaStatements#add_timestamps
      def timestamps(options = {})
        @base.add_timestamps(name, options)
      end

      # Changes the column's definition according to the new options.
      #
      #  t.change(:name, :string, limit: 80)
      #  t.change(:description, :text)
      #
      # See TableDefinition#column for details of the options you can use.
      def change(column_name, type, options = {})
        @base.change_column(name, column_name, type, options)
      end

      # Sets a new default value for a column.
      #
      #  t.change_default(:qualification, 'new')
      #  t.change_default(:authorized, 1)
      #
      # See SchemaStatements#change_column_default
      def change_default(column_name, default)
        @base.change_column_default(name, column_name, default)
      end

      # Removes the column(s) from the table definition.
      #
      #  t.remove(:qualification)
      #  t.remove(:qualification, :experience)
      #
      # See SchemaStatements#remove_columns
      def remove(*column_names)
        @base.remove_columns(name, *column_names)
      end

      # Removes the given index from the table.
      #
      #   t.remove_index(:branch_id)
      #   t.remove_index(column: [:branch_id, :party_id])
      #   t.remove_index(name: :by_branch_party)
      #
      # See SchemaStatements#remove_index
      def remove_index(options = {})
        @base.remove_index(name, options)
      end

      # Removes the timestamp columns (+created_at+ and +updated_at+) from the table.
      #
      #  t.remove_timestamps
      #
      # See SchemaStatements#remove_timestamps
      def remove_timestamps(options = {})
        @base.remove_timestamps(name, options)
      end

      # Renames a column.
      #
      #  t.rename(:description, :name)
      #
      # See SchemaStatements#rename_column
      def rename(column_name, new_column_name)
        @base.rename_column(name, column_name, new_column_name)
      end

      # Adds a reference. Optionally adds a +type+ column, if
      # <tt>:polymorphic</tt> option is provided.
      #
      #  t.references(:user)
      #  t.references(:user, type: "string")
      #  t.belongs_to(:supplier, polymorphic: true)
      #  t.belongs_to(:supplier, foreign_key: true)
      #
      # See SchemaStatements#add_reference
      def references(*args)
        options = args.extract_options!
        args.each do |ref_name|
          @base.add_reference(name, ref_name, options)
        end
      end
      alias :belongs_to :references

      # Removes a reference. Optionally removes a +type+ column.
      #
      #  t.remove_references(:user)
      #  t.remove_belongs_to(:supplier, polymorphic: true)
      #
      # See SchemaStatements#remove_reference
      def remove_references(*args)
        options = args.extract_options!
        args.each do |ref_name|
          @base.remove_reference(name, ref_name, options)
        end
      end
      alias :remove_belongs_to :remove_references

      # Adds a foreign key.
      #
      # t.foreign_key(:authors)
      #
      # See SchemaStatements#add_foreign_key
      def foreign_key(*args) # :nodoc:
        @base.add_foreign_key(name, *args)
      end

      # Checks to see if a foreign key exists.
      #
      # t.foreign_key(:authors) unless t.foreign_key_exists?(:authors)
      #
      # See SchemaStatements#foreign_key_exists?
      def foreign_key_exists?(*args) # :nodoc:
        @base.foreign_key_exists?(name, *args)
      end

      private
        def native
          @base.native_database_types
        end
    end
  end
end
