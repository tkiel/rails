# frozen_string_literal: true

module ActiveRecord
  module Associations
    class Preloader
      class HasMany < CollectionAssociation #:nodoc:
        def association_key_name
          reflection.foreign_key
        end
      end
    end
  end
end
