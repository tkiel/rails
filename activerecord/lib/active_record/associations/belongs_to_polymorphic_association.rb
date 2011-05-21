module ActiveRecord
  # = Active Record Belongs To Polymorphic Association
  module Associations
    class BelongsToPolymorphicAssociation < BelongsToAssociation #:nodoc:
      private

        def replace_keys(record)
          super
          owner[reflection.foreign_type] = record && record.class.base_class.name
        end

        def different_target?(record)
          super || record.class != klass
        end

        def inverse_reflection_for(record)
          reflection.polymorphic_inverse_of(record.class)
        end

        def klass
          type = owner[reflection.foreign_type]
          type.presence && type.constantize
        end

        def raise_on_type_mismatch(record)
          # A polymorphic association cannot have a type mismatch, by definition
        end

        def stale_state
          [super, owner[reflection.foreign_type].to_s]
        end
    end
  end
end
