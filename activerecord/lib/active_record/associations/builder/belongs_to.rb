module ActiveRecord::Associations::Builder # :nodoc:
  class BelongsTo < SingularAssociation #:nodoc:
    def self.macro
      :belongs_to
    end

    def self.valid_options(options)
      super + [:foreign_type, :polymorphic, :touch, :counter_cache, :optional]
    end

    def self.valid_dependent_options
      [:destroy, :delete]
    end

    def self.define_callbacks(model, reflection)
      super
      add_counter_cache_callbacks(model, reflection) if reflection.options[:counter_cache]
      add_touch_callbacks(model, reflection)         if reflection.options[:touch]
    end

    def self.define_accessors(mixin, reflection)
      super
      add_counter_cache_methods mixin
    end

    def self.add_counter_cache_methods(mixin)
      return if mixin.method_defined? :belongs_to_counter_cache_after_update

      mixin.class_eval do
        def belongs_to_counter_cache_after_update(reflection)
          foreign_key  = reflection.foreign_key
          cache_column = reflection.counter_cache_column

          if (@_after_create_counter_called ||= false)
            @_after_create_counter_called = false
          elsif attribute_changed?(foreign_key) && !new_record?
            if reflection.polymorphic?
              model     = attribute(reflection.foreign_type).try(:constantize)
              model_was = attribute_was(reflection.foreign_type).try(:constantize)
            else
              model     = reflection.klass
              model_was = reflection.klass
            end

            foreign_key_was = attribute_was foreign_key
            foreign_key     = attribute foreign_key

            if foreign_key && model.respond_to?(:increment_counter)
              model.increment_counter(cache_column, foreign_key)
            end

            if foreign_key_was && model_was.respond_to?(:decrement_counter)
              model_was.decrement_counter(cache_column, foreign_key_was)
            end
          end
        end
      end
    end

    def self.add_counter_cache_callbacks(model, reflection)
      cache_column = reflection.counter_cache_column

      model.after_update lambda { |record|
        record.belongs_to_counter_cache_after_update(reflection)
      }

      klass = reflection.class_name.safe_constantize
      klass.attr_readonly cache_column if klass && klass.respond_to?(:attr_readonly)
    end

    def self.touch_record(o, foreign_key, name, touch, touch_method) # :nodoc:
      old_foreign_id = o.changed_attributes[foreign_key]

      if old_foreign_id
        association = o.association(name)
        reflection = association.reflection
        if reflection.polymorphic?
          klass = o.public_send("#{reflection.foreign_type}_was").constantize
        else
          klass = association.klass
        end
        old_record = klass.find_by(klass.primary_key => old_foreign_id)

        if old_record
          if touch != true
            old_record.send(touch_method, touch)
          else
            old_record.send(touch_method)
          end
        end
      end

      record = o.send name
      if record && record.persisted?
        if touch != true
          record.send(touch_method, touch)
        else
          record.send(touch_method)
        end
      end
    end

    def self.add_touch_callbacks(model, reflection)
      foreign_key = reflection.foreign_key
      n           = reflection.name
      touch       = reflection.options[:touch]

      callback = lambda { |record|
        touch_method = touching_delayed_records? ? :touch : :touch_later
        BelongsTo.touch_record(record, foreign_key, n, touch, touch_method)
      }

      model.after_save    callback, if: :changed?
      model.after_touch   callback
      model.after_destroy callback
    end

    def self.add_destroy_callbacks(model, reflection)
      model.after_destroy lambda { |o| o.association(reflection.name).handle_dependency }
    end

    def self.define_validations(model, reflection)
      if reflection.options.key?(:required)
        reflection.options[:optional] = !reflection.options.delete(:required)
      end

      if reflection.options[:optional].nil?
        required = model.belongs_to_required_by_default
      else
        required = !reflection.options[:optional]
      end

      super

      if required
        model.validates_presence_of reflection.name, message: :required
      end
    end
  end
end
