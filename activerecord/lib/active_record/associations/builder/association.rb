module ActiveRecord::Associations::Builder
  class Association #:nodoc:
    class << self
      attr_accessor :valid_options
    end

    self.valid_options = [:class_name, :foreign_key, :validate]

    attr_reader :model, :name, :scope, :options, :reflection

    def self.build(*args, &block)
      new(*args, &block).build
    end

    def initialize(model, name, scope, options)
      @model   = model
      @name    = name

      if scope.is_a?(Hash)
        @scope   = nil
        @options = scope
      else
        @scope   = scope
        @options = options
      end

      if @scope && @scope.arity == 0
        prev_scope = @scope
        @scope = proc { instance_exec(&prev_scope) }
      end
    end

    def mixin
      @model.generated_feature_methods
    end

    include Module.new { def build; end }

    def build
      validate_options
      define_accessors
      @reflection = model.create_reflection(macro, name, scope, options, model)
      super # provides an extension point
      @reflection
    end

    def macro
      raise NotImplementedError
    end

    def valid_options
      Association.valid_options
    end

    private

      def validate_options
        options.assert_valid_keys(valid_options)
      end

      def define_accessors
        define_readers
        define_writers
      end

      def define_readers
        name = self.name
        mixin.redefine_method(name) do |*params|
          association(name).reader(*params)
        end
      end

      def define_writers
        name = self.name
        mixin.redefine_method("#{name}=") do |value|
          association(name).writer(value)
        end
      end

      def check_valid_dependent!(dependent, valid_options)
        unless valid_options.include?(dependent)
          valid_options_message = valid_options.map(&:inspect).to_sentence(
            words_connector: ', ', two_words_connector: ' or ', last_word_connector: ' or ')

          raise ArgumentError, "The :dependent option expects either " \
            "#{valid_options_message} (#{dependent.inspect})"
        end

        if dependent == :restrict
          ActiveSupport::Deprecation.warn(
            "The :restrict option is deprecated. Please use :restrict_with_exception instead, which " \
            "provides the same functionality."
          )
        end
      end

      def define_restrict_with_exception_dependency_method
        name = self.name
        mixin.redefine_method(dependency_method_name) do
          has_one_macro = association(name).reflection.macro == :has_one
          if has_one_macro ? !send(name).nil? : send(name).exists?
            raise ActiveRecord::DeleteRestrictionError.new(name)
          end
        end
      end
      alias define_restrict_dependency_method define_restrict_with_exception_dependency_method

      def define_restrict_with_error_dependency_method
        name = self.name
        mixin.redefine_method(dependency_method_name) do
          has_one_macro = association(name).reflection.macro == :has_one
          if has_one_macro ? !send(name).nil? : send(name).exists?
            key  = has_one_macro ? "one" : "many"
            errors.add(:base, :"restrict_dependent_destroy.#{key}",
                       :record => self.class.human_attribute_name(name).downcase)
            false
          end
        end
      end
  end
end
