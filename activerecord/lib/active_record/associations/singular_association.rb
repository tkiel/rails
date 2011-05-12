module ActiveRecord
  module Associations
    class SingularAssociation < Association #:nodoc:
      # Implements the reader method, e.g. foo.bar for Foo.has_one :bar
      def reader(force_reload = false)
        if force_reload
          klass.uncached { reload }
        elsif !loaded? || stale_target?
          reload
        end

        target
      end

      # Implements the writer method, e.g. foo.items= for Foo.has_many :items
      def writer(record)
        replace(record)
      end

      def create(attributes = {}, options = {})
        build(attributes, options).tap { |record| record.save }
      end

      def create!(attributes = {}, options = {})
        build(attributes, options).tap { |record| record.save! }
      end

      def build(attributes = {}, options = {})
        record = reflection.build_association
        record.assign_attributes(
          scoped.scope_for_create.except(klass.primary_key),
          :without_protection => true
        )
        record.assign_attributes(attributes, options)
        set_new_record(record)
        record
      end

      private

        def find_target
          scoped.first.tap { |record| set_inverse_instance(record) }
        end

        # Implemented by subclasses
        def replace(record)
          raise NotImplementedError, "Subclasses must implement a replace(record) method"
        end

        def set_new_record(record)
          replace(record)
        end
    end
  end
end
