module ActiveRecord
  module Associations
    class AssociationScope #:nodoc:
      def self.scope(association, connection)
        INSTANCE.scope association, connection
      end

      class BindSubstitution
        def initialize(block)
          @block = block
        end

        def bind_value(scope, column, value, connection)
          substitute = connection.substitute_at(column)
          scope.bind_values += [[column, @block.call(value)]]
          substitute
        end
      end

      def self.create(&block)
        block = block ? block : lambda { |val| val }
        new BindSubstitution.new(block)
      end

      def initialize(bind_substitution)
        @bind_substitution = bind_substitution
      end

      INSTANCE = create

      def scope(association, connection)
        klass         = association.klass
        reflection    = association.reflection
        scope         = klass.unscoped
        owner         = association.owner
        alias_tracker = AliasTracker.empty connection
        chain         = get_chain(reflection, association)

        scope.extending! Array(reflection.options[:extend])
        add_constraints(scope, owner, klass, reflection, alias_tracker, chain)
      end

      def join_type
        Arel::Nodes::InnerJoin
      end

      def self.get_bind_values(owner, chain)
        binds = []
        last_reflection = chain.last

        binds << last_reflection.join_id_for(owner)
        if last_reflection.type
          binds << owner.class.base_class.name
        end

        chain.each_cons(2).each do |reflection, next_reflection|
          if reflection.type
            binds << next_reflection.klass.base_class.name
          end
        end
        binds
      end

      private

      def construct_tables(chain, klass, refl, alias_tracker)
        chain.map do |reflection|
          alias_tracker.aliased_table_for(
            table_name_for(reflection, klass, refl),
            table_alias_for(reflection, refl, reflection != refl),
            type_caster: klass.type_caster,
          )
        end
      end

      def table_alias_for(reflection, refl, join = false)
        name = "#{reflection.plural_name}_#{alias_suffix(refl)}"
        name << "_join" if join
        name
      end

      def join(table, constraint)
        table.create_join(table, table.create_on(constraint), join_type)
      end

      def column_for(table_name, column_name, connection)
        columns = connection.schema_cache.columns_hash(table_name)
        columns[column_name]
      end

      def bind_value(scope, column, value, connection)
        @bind_substitution.bind_value scope, column, value, connection
      end

      def bind(scope, table_name, column_name, value, connection)
        column   = column_for table_name, column_name, connection
        bind_value scope, column, value, connection
      end

      def last_chain_scope(scope, table, reflection, owner, connection, assoc_klass)
        join_keys = reflection.join_keys(assoc_klass)
        key = join_keys.key
        foreign_key = join_keys.foreign_key

        bind_val = bind scope, table.table_name, key.to_s, owner[foreign_key], connection
        scope    = scope.where(table[key].eq(bind_val))

        if reflection.type
          value    = owner.class.base_class.name
          bind_val = bind scope, table.table_name, reflection.type, value, connection
          scope    = scope.where(table[reflection.type].eq(bind_val))
        else
          scope
        end
      end

      def next_chain_scope(scope, table, reflection, connection, assoc_klass, foreign_table, next_reflection)
        join_keys = reflection.join_keys(assoc_klass)
        key = join_keys.key
        foreign_key = join_keys.foreign_key

        constraint = table[key].eq(foreign_table[foreign_key])

        if reflection.type
          value    = next_reflection.klass.base_class.name
          bind_val = bind scope, table.table_name, reflection.type, value, connection
          scope    = scope.where(table[reflection.type].eq(bind_val))
        end

        scope = scope.joins(join(foreign_table, constraint))
      end

      class RuntimeReflection
        def initialize(reflection, association)
          @reflection = reflection
          @association = association
        end

        def klass
          @association.klass
        end

        def scope
          @reflection.scope
        end

        def table_name
          if @reflection.polymorphic?
            # If this is a polymorphic belongs_to, we want to get the klass from the
            # association because it depends on the polymorphic_type attribute of
            # the owner
            klass.table_name
          else
            @reflection.table_name
          end
        end

        def plural_name
          @reflection.plural_name
        end

        def join_keys(assoc_klass)
          @reflection.join_keys(assoc_klass)
        end

        def type
          @reflection.type
        end

        def constraints
          @reflection.constraints
        end

        def source_type_info
          @reflection.source_type_info
        end
      end

      def get_chain(reflection, association)
        chain = reflection.chain.dup
        chain[0] = RuntimeReflection.new(reflection, association)
        chain
      end

      def add_constraints(scope, owner, assoc_klass, refl, tracker, chain)
        tables = construct_tables(chain, assoc_klass, refl, tracker)

        owner_reflection = chain.last
        table = tables.last
        scope = last_chain_scope(scope, table, owner_reflection, owner, connection, assoc_klass)

        # chain.first always == refl
        chain.each_with_index do |reflection, i|
          table, foreign_table = tables.shift, tables.first

          unless reflection == chain.last
            next_reflection = chain[i + 1]
            scope = next_chain_scope(scope, table, reflection, connection, assoc_klass, foreign_table, next_reflection)
          end

          is_first_chain = i == 0
          klass = is_first_chain ? assoc_klass : reflection.klass

          items = reflection.constraints

          # Exclude the scope of the association itself, because that
          # was already merged in the #scope method.
          items.each do |scope_chain_item|
            item  = eval_scope(klass, scope_chain_item, owner)

            if scope_chain_item == refl.scope
              scope.merge! item.except(:where, :includes, :bind)
            end

            if is_first_chain
              scope.includes! item.includes_values
            end

            scope.where_values += item.where_values
            scope.bind_values  += item.bind_values
            scope.order_values |= item.order_values
          end
        end

        scope
      end

      def alias_suffix(refl)
        refl.name
      end

      def table_name_for(reflection, klass, refl)
        if reflection == refl
          # If this is a polymorphic belongs_to, we want to get the klass from the
          # association because it depends on the polymorphic_type attribute of
          # the owner
          klass.table_name
        else
          reflection.table_name
        end
      end

      def eval_scope(klass, scope, owner)
        klass.unscoped.instance_exec(owner, &scope)
      end
    end
  end
end
