# frozen_string_literal: true

module ActiveRecord
  ###
  # This class encapsulates a result returned from calling
  # {#exec_query}[rdoc-ref:ConnectionAdapters::DatabaseStatements#exec_query]
  # on any database connection adapter. For example:
  #
  #   result = ActiveRecord::Base.connection.exec_query('SELECT id, title, body FROM posts')
  #   result # => #<ActiveRecord::Result:0xdeadbeef>
  #
  #   # Get the column names of the result:
  #   result.columns
  #   # => ["id", "title", "body"]
  #
  #   # Get the record values of the result:
  #   result.rows
  #   # => [[1, "title_1", "body_1"],
  #         [2, "title_2", "body_2"],
  #         ...
  #        ]
  #
  #   # Get an array of hashes representing the result (column => value):
  #   result.to_hash
  #   # => [{"id" => 1, "title" => "title_1", "body" => "body_1"},
  #         {"id" => 2, "title" => "title_2", "body" => "body_2"},
  #         ...
  #        ]
  #
  #   # ActiveRecord::Result also includes Enumerable.
  #   result.each do |row|
  #     puts row['title'] + " " + row['body']
  #   end
  class Result
    include Enumerable

    attr_reader :columns, :rows, :column_types

    def initialize(columns, rows, column_types = {})
      @columns      = columns
      @rows         = rows
      @hash_rows    = nil
      @column_types = column_types
    end

    # Does this result set include the column named +name+ ?
    def includes_column?(name)
      @columns.include? name
    end

    # Returns the number of elements in the rows array.
    def length
      @rows.length
    end

    # Calls the given block once for each element in row collection, passing
    # row as parameter.
    #
    # Returns an +Enumerator+ if no block is given.
    def each
      if block_given?
        hash_rows.each { |row| yield row }
      else
        hash_rows.to_enum { @rows.size }
      end
    end

    # Returns an array of hashes representing each row record.
    def to_hash
      hash_rows
    end

    alias :map! :map
    alias :collect! :map

    # Returns true if there are no records, otherwise false.
    def empty?
      rows.empty?
    end

    # Returns an array of hashes representing each row record.
    def to_ary
      hash_rows
    end

    def [](idx)
      hash_rows[idx]
    end

    # Returns the first record from the rows collection.
    # If the rows collection is empty, returns +nil+.
    def first
      return nil if @rows.empty?
      Hash[@columns.zip(@rows.first)]
    end

    # Returns the last record from the rows collection.
    # If the rows collection is empty, returns +nil+.
    def last
      return nil if @rows.empty?
      Hash[@columns.zip(@rows.last)]
    end

    def cast_values(type_overrides = {}) # :nodoc:
      if columns.one?
        # Separated to avoid allocating an array per row

        type = column_type(columns.first, type_overrides)

        rows.map do |(value)|
          type.deserialize(value)
        end
      else
        types = columns.map { |name| column_type(name, type_overrides) }

        rows.map do |values|
          Array.new(values.size) { |i| types[i].deserialize(values[i]) }
        end
      end
    end

    def initialize_copy(other)
      @columns      = columns.dup
      @rows         = rows.dup
      @column_types = column_types.dup
      @hash_rows    = nil
    end

    private

      def column_type(name, type_overrides = {})
        type_overrides.fetch(name) do
          column_types.fetch(name, Type.default_value)
        end
      end

      def hash_rows
        @hash_rows ||=
          begin
            # We freeze the strings to prevent them getting duped when
            # used as keys in ActiveRecord::Base's @attributes hash
            columns = @columns.map(&:-@)
            @rows.map { |row|
              # In the past we used Hash[columns.zip(row)]
              #  though elegant, the verbose way is much more efficient
              #  both time and memory wise cause it avoids a big array allocation
              #  this method is called a lot and needs to be micro optimised
              hash = {}

              index = 0
              length = columns.length

              while index < length
                hash[columns[index]] = row[index]
                index += 1
              end

              hash
            }
          end
      end
  end
end
