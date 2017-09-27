# frozen_string_literal: true

require "active_support/core_ext/module/attribute_accessors"
require_relative "../attribute_mutation_tracker"

module ActiveRecord
  module AttributeMethods
    module Dirty
      extend ActiveSupport::Concern

      include ActiveModel::Dirty

      included do
        if self < ::ActiveRecord::Timestamp
          raise "You cannot include Dirty after Timestamp"
        end

        class_attribute :partial_writes, instance_writer: false, default: true

        after_create { changes_applied }
        after_update { changes_applied }

        # Attribute methods for "changed in last call to save?"
        attribute_method_affix(prefix: "saved_change_to_", suffix: "?")
        attribute_method_prefix("saved_change_to_")
        attribute_method_suffix("_before_last_save")

        # Attribute methods for "will change if I call save?"
        attribute_method_affix(prefix: "will_save_change_to_", suffix: "?")
        attribute_method_suffix("_change_to_be_saved", "_in_database")
      end

      # <tt>reload</tt> the record and clears changed attributes.
      def reload(*)
        super.tap do
          @mutations_before_last_save = nil
          @mutations_from_database = nil
          @changed_attributes = ActiveSupport::HashWithIndifferentAccess.new
        end
      end

      def initialize_dup(other) # :nodoc:
        super
        @attributes = self.class._default_attributes.map do |attr|
          attr.with_value_from_user(@attributes.fetch_value(attr.name))
        end
        @mutations_from_database = nil
      end

      def changes_applied # :nodoc:
        @mutations_before_last_save = mutations_from_database
        @changed_attributes = ActiveSupport::HashWithIndifferentAccess.new
        forget_attribute_assignments
        @mutations_from_database = nil
      end

      def clear_changes_information # :nodoc:
        @mutations_before_last_save = nil
        @changed_attributes = ActiveSupport::HashWithIndifferentAccess.new
        forget_attribute_assignments
        @mutations_from_database = nil
      end

      def clear_attribute_changes(attr_names) # :nodoc:
        super
        attr_names.each do |attr_name|
          clear_attribute_change(attr_name)
        end
      end

      def changed_attributes # :nodoc:
        # This should only be set by methods which will call changed_attributes
        # multiple times when it is known that the computed value cannot change.
        if defined?(@cached_changed_attributes)
          @cached_changed_attributes
        else
          super.reverse_merge(mutations_from_database.changed_values).freeze
        end
      end

      def changes # :nodoc:
        cache_changed_attributes do
          super
        end
      end

      def previous_changes # :nodoc:
        mutations_before_last_save.changes
      end

      def attribute_changed_in_place?(attr_name) # :nodoc:
        mutations_from_database.changed_in_place?(attr_name)
      end

      # Did this attribute change when we last saved? This method can be invoked
      # as +saved_change_to_name?+ instead of <tt>saved_change_to_attribute?("name")</tt>.
      # Behaves similarly to +attribute_changed?+. This method is useful in
      # after callbacks to determine if the call to save changed a certain
      # attribute.
      #
      # ==== Options
      #
      # +from+ When passed, this method will return false unless the original
      # value is equal to the given option
      #
      # +to+ When passed, this method will return false unless the value was
      # changed to the given value
      def saved_change_to_attribute?(attr_name, **options)
        mutations_before_last_save.changed?(attr_name, **options)
      end

      # Returns the change to an attribute during the last save. If the
      # attribute was changed, the result will be an array containing the
      # original value and the saved value.
      #
      # Behaves similarly to +attribute_change+. This method is useful in after
      # callbacks, to see the change in an attribute that just occurred
      #
      # This method can be invoked as +saved_change_to_name+ in instead of
      # <tt>saved_change_to_attribute("name")</tt>
      def saved_change_to_attribute(attr_name)
        mutations_before_last_save.change_to_attribute(attr_name)
      end

      # Returns the original value of an attribute before the last save.
      # Behaves similarly to +attribute_was+. This method is useful in after
      # callbacks to get the original value of an attribute before the save that
      # just occurred
      def attribute_before_last_save(attr_name)
        mutations_before_last_save.original_value(attr_name)
      end

      # Did the last call to +save+ have any changes to change?
      def saved_changes?
        mutations_before_last_save.any_changes?
      end

      # Returns a hash containing all the changes that were just saved.
      def saved_changes
        mutations_before_last_save.changes
      end

      # Alias for +attribute_changed?+
      def will_save_change_to_attribute?(attr_name, **options)
        mutations_from_database.changed?(attr_name, **options)
      end

      # Alias for +attribute_change+
      def attribute_change_to_be_saved(attr_name)
        mutations_from_database.change_to_attribute(attr_name)
      end

      # Alias for +attribute_was+
      def attribute_in_database(attr_name)
        mutations_from_database.original_value(attr_name)
      end

      # Alias for +changed?+
      def has_changes_to_save?
        mutations_from_database.any_changes?
      end

      # Alias for +changes+
      def changes_to_save
        mutations_from_database.changes
      end

      # Alias for +changed+
      def changed_attribute_names_to_save
        changes_to_save.keys
      end

      # Alias for +changed_attributes+
      def attributes_in_database
        changes_to_save.transform_values(&:first)
      end

      private
        def write_attribute_without_type_cast(attr_name, _)
          result = super
          clear_attribute_change(attr_name)
          result
        end

        def mutations_from_database
          unless defined?(@mutations_from_database)
            @mutations_from_database = nil
          end
          @mutations_from_database ||= AttributeMutationTracker.new(@attributes)
        end

        def changes_include?(attr_name)
          super || mutations_from_database.changed?(attr_name)
        end

        def clear_attribute_change(attr_name)
          mutations_from_database.forget_change(attr_name)
        end

        def attribute_will_change!(attr_name)
          super
          mutations_from_database.force_change(attr_name)
        end

        def _update_record(*)
          partial_writes? ? super(keys_for_partial_write) : super
        end

        def _create_record(*)
          partial_writes? ? super(keys_for_partial_write) : super
        end

        def keys_for_partial_write
          changed_attribute_names_to_save & self.class.column_names
        end

        def forget_attribute_assignments
          @attributes = @attributes.map(&:forgetting_assignment)
        end

        def mutations_before_last_save
          @mutations_before_last_save ||= NullMutationTracker.instance
        end

        def cache_changed_attributes
          @cached_changed_attributes = changed_attributes
          yield
        ensure
          clear_changed_attributes_cache
        end

        def clear_changed_attributes_cache
          remove_instance_variable(:@cached_changed_attributes) if defined?(@cached_changed_attributes)
        end
    end
  end
end
