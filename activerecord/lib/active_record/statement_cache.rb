module ActiveRecord

  # Statement cache is used to cache a single statement in order to avoid creating the AST again.
  # Initializing the cache is done by passing the statement in the initialization block:
  #
  #   cache = ActiveRecord::StatementCache.new do
  #     Book.where(name: "my book").limit(100)
  #   end
  #
  # The cached statement is executed by using the +execute+ method:
  #
  #   cache.execute
  #
  # The relation returned by the block is cached, and for each +execute+ call the cached relation gets duped.
  # Database is queried when +to_a+ is called on the relation.
  class StatementCache
    Substitute = Struct.new :name

    class Query
      def initialize(sql)
        @sql = sql
      end

      def sql_for(binds, connection)
        @sql
      end
    end

    class PartialQuery < Query
      def initialize values
        @values = values
        @indexes = values.each_with_index.find_all { |thing,i|
          Arel::Nodes::BindParam === thing
        }.map(&:last)
      end

      def sql_for(binds, connection)
        val = @values.dup
        binds = binds.dup
        @indexes.each { |i| val[i] = connection.quote(*binds.shift.reverse) }
        val.join
      end
    end

    def self.query(visitor, ast)
      Query.new visitor.accept(ast, Arel::Collectors::SQLString.new).value
    end

    def self.partial_query(visitor, ast, collector)
      collected = visitor.accept(ast, collector).value
      PartialQuery.new collected
    end

    class Params
      def [](name); Substitute.new name; end
    end

    class BindMap
      def initialize(bind_values)
        @value_map   = {}
        @bind_values = bind_values

        bind_values.each_with_index do |(_, value), i|
          if Substitute === value
            @value_map[value.name] = i
          end
        end
      end

      def bind(values)
        bvs = @bind_values.map { |pair| pair.dup }
        values.each { |k,v| bvs[@value_map[k]][1] = v }
        bvs
      end
    end

    attr_reader :bind_map, :query_builder

    def self.create(connection, block = Proc.new)
      relation      = block.call Params.new
      bind_map      = BindMap.new relation.bind_values
      query_builder = connection.cacheable_query relation.arel
      new query_builder, bind_map
    end

    def initialize(query_builder, bind_map)
      @query_builder = query_builder
      @bind_map      = bind_map
    end

    def execute(params, klass, connection)
      bind_values = bind_map.bind params

      sql = query_builder.sql_for bind_values, connection

      klass.find_by_sql sql, bind_values
    end
    alias :call :execute
  end
end
