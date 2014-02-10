module ActiveRecord
  module Associations
    # Helper class module which gets mixed into JoinDependency::JoinAssociation and AssociationScope
    module JoinHelper #:nodoc:

      def join_type
        Arel::Nodes::InnerJoin
      end

      private

      def construct_tables
        chain.map do |reflection|
          alias_tracker.aliased_table_for(
            table_name_for(reflection),
            table_alias_for(reflection, reflection != self.reflection)
          )
        end
      end

      def table_name_for(reflection)
        reflection.table_name
      end

      def table_alias_for(reflection, join = false)
        name = "#{reflection.plural_name}_#{alias_suffix}"
        name << "_join" if join
        name
      end

      def join(table, constraint)
        table.create_join(table, table.create_on(constraint), join_type)
      end
    end
  end
end
