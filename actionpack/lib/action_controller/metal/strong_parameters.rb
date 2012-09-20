require 'active_support/concern'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/rescuable'

module ActionController
  # Raised when a required parameter is missing.
  #
  #   params = ActionController::Parameters.new(a: {})
  #   params.fetch(:b)
  #   # => ActionController::ParameterMissing: key not found: b
  #   params.require(:a)
  #   # => ActionController::ParameterMissing: key not found: a
  class ParameterMissing < KeyError
    attr_reader :param # :nodoc:

    def initialize(param) # :nodoc:
      @param = param
      super("key not found: #{param}")
    end
  end

  # == Action Controller Parameters
  #
  # Allows to choose which attributes should be whitelisted for mass updating
  # and thus prevent accidentally exposing that which shouldn’t be exposed.
  # Provides two methods for this purpose: #require and #permit. The former is
  # used to mark parameters as required. The latter is used to set the parameter
  # as permitted and limit which attributes should be allowed for mass updating.
  #
  #   params = ActionController::Parameters.new({
  #     person: {
  #       name: 'Francesco',
  #       age:  22,
  #       role: 'admin'
  #     }
  #   })
  #
  #   permitted = params.require(:person).permit(:name, :age)
  #   permitted            # => {"name"=>"Francesco", "age"=>22}
  #   permitted.class      # => ActionController::Parameters
  #   permitted.permitted? # => true
  #
  #   Person.first.update_attributes!(permitted) # => #<Person id: 1, name: "Francesco", age: 22, role: "user">
  #
  # It provides a <tt>permit_all_parameters</tt> option that
  # controls the top-level behaviour of new instances. If it's +true+,
  # all the parameters will be permitted by default. The default value
  # for <tt>permit_all_parameters</tt> option is +false+.
  #
  #   params = ActionController::Parameters.new
  #   params.permitted? # => false
  #
  #   ActionController::Parameters.permit_all_parameters = true
  #
  #   params = ActionController::Parameters.new
  #   params.permitted? # => true
  #
  # <tt>ActionController::Parameters</tt> is inherited from
  # <tt>ActiveSupport::HashWithIndifferentAccess</tt>, this means
  # that you can fetch values using either <tt>:key</tt> or <tt>"key"</tt>.
  #
  #   params = ActionController::Parameters.new(key: 'value')
  #   params[:key]  # => "value"
  #   params["key"] # => "value"
  class Parameters < ActiveSupport::HashWithIndifferentAccess
    cattr_accessor :permit_all_parameters, instance_accessor: false
    attr_accessor :permitted # :nodoc:
    alias :permitted? :permitted

    # Returns a new instance of <tt>ActionController::Parameters</tt>.
    # Also, sets the +permitted+ attribute to the default value of
    # <tt>ActionController::Parameters.permit_all_parameters</tt>.
    #
    #   class Person
    #     include ActiveRecord::Base
    #   end
    #
    #   params = ActionController::Parameters.new(name: 'Francesco')
    #   params.permitted?  # => false
    #   Person.new(params) # => ActiveModel::ForbiddenAttributesError
    #
    #   ActionController::Parameters.permit_all_parameters = true
    #
    #   params = ActionController::Parameters.new(name: 'Francesco')
    #   params.permitted?  # => true
    #   Person.new(params) # => #<Person id: nil, name: "Francesco">
    def initialize(attributes = nil)
      super(attributes)
      @permitted = self.class.permit_all_parameters
    end

    # Sets the +permitted+ attribute to +true+. This can be used to pass
    # mass assignment. Returns +self+.
    #
    #   class Person < ActiveRecord::Base
    #   end
    #
    #   params = ActionController::Parameters.new(name: 'Francesco')
    #   params.permitted?  # => false
    #   Person.new(params) # => ActiveModel::ForbiddenAttributesError
    #   params.permit!
    #   params.permitted?  # => true
    #   Person.new(params) # => #<Person id: nil, name: "Francesco">
    def permit!
      @permitted = true
      self
    end

    # Ensures that a parameter is present. If it's present, returns
    # the parameter at the given +key+, otherwise raises an
    # <tt>ActionController::ParameterMissing</tt> error.
    #
    #   ActionController::Parameters.new(person: { name: 'Francesco' }).require(:person)
    #   # => {"name"=>"Francesco"}
    #
    #   ActionController::Parameters.new(person: nil).require(:person)
    #   # => ActionController::ParameterMissing: key not found: person
    #
    #   ActionController::Parameters.new(person: {}).require(:person)
    #   # => ActionController::ParameterMissing: key not found: person
    def require(key)
      self[key].presence || raise(ParameterMissing.new(key))
    end

    # Alias of #require.
    alias :required :require

    # Returns a new <tt>ActionController::Parameters</tt> instance that
    # includes only the given +filters+ and sets the +permitted+ for the
    # object to +true+. This is useful for limiting which attributes
    # should be allowed for mass updating.
    #
    #   params = ActionController::Parameters.new(user: { name: 'Francesco', age: 22, role: 'admin' })
    #   permitted = params.require(:user).permit(:name, :age)
    #   permitted.permitted?      # => true
    #   permitted.has_key?(:name) # => true
    #   permitted.has_key?(:age)  # => true
    #   permitted.has_key?(:role) # => false
    #
    # You can also use +permit+ on nested parameters, like:
    #
    #   params = ActionController::Parameters.new({
    #     person: {
    #       name: 'Francesco',
    #       age:  22,
    #       pets: [{
    #         name: 'Purplish',
    #         category: 'dogs'
    #       }]
    #     }
    #   })
    #
    #   permitted = params.permit(person: [ :name, { pets: [ :name ] } ])
    #   permitted.permitted?                    # => true
    #   permitted[:person][:name]               # => "Francesco"
    #   permitted[:person][:age]                # => nil
    #   permitted[:person][:pets][0][:name]     # => "Purplish"
    #   permitted[:person][:pets][0][:category] # => nil
    def permit(*filters)
      params = self.class.new

      filters.each do |filter|
        case filter
        when Symbol, String then
          params[filter] = self[filter] if has_key?(filter)
        when Hash then
          self.slice(*filter.keys).each do |key, values|
            return unless values

            key = key.to_sym

            params[key] = each_element(values) do |value|
              # filters are a Hash, so we expect value to be a Hash too
              next if filter.is_a?(Hash) && !value.is_a?(Hash)

              value = self.class.new(value) if !value.respond_to?(:permit)

              value.permit(*Array.wrap(filter[key]))
            end
          end
        end
      end

      params.permit!
    end

    # Returns a parameter for the given +key+. If not found,
    # returns +nil+.
    #
    #   params = ActionController::Parameters.new(person: { name: 'Francesco' })
    #   params[:person] # => {"name"=>"Francesco"}
    #   params[:none]   # => nil
    def [](key)
      convert_hashes_to_parameters(key, super)
    end

    # Returns a parameter for the given +key+. If the +key+
    # can't be found, there are several options: With no other arguments,
    # it will raise an <tt>ActionController::ParameterMissing</tt> error;
    # if more arguments are given, then that will be returned; if a block
    # is given, then that will be run and its result returned.
    #
    #   params = ActionController::Parameters.new(person: { name: 'Francesco' })
    #   params.fetch(:person)         # => {"name"=>"Francesco"}
    #   params.fetch(:none)           # => ActionController::ParameterMissing: key not found: none
    #   params.fetch(:none, 'Francesco')    # => "Francesco"
    #   params.fetch(:none) { 'Francesco' } # => "Francesco"
    def fetch(key, *args)
      convert_hashes_to_parameters(key, super)
    rescue KeyError
      raise ActionController::ParameterMissing.new(key)
    end

    # Returns a new <tt>ActionController::Parameters</tt> instance that
    # includes only the given +keys+. If the given +keys+
    # don't exist, returns an empty hash.
    #
    #   params = ActionController::Parameters.new(a: 1, b: 2, c: 3)
    #   params.slice(:a, :b) # => {"a"=>1, "b"=>2}
    #   params.slice(:d)     # => {}
    def slice(*keys)
      self.class.new(super)
    end

    # Returns an exact copy of the <tt>ActionController::Parameters</tt>
    # instance. +permitted+ state is kept on the duped object.
    #
    #   params = ActionController::Parameters.new(a: 1)
    #   params.permit!
    #   params.permitted?        # => true
    #   copy_params = params.dup # => {"a"=>1}
    #   copy_params.permitted?   # => true
    def dup
      super.tap do |duplicate|
        duplicate.instance_variable_set :@permitted, @permitted
      end
    end

    private
      def convert_hashes_to_parameters(key, value)
        if value.is_a?(Parameters) || !value.is_a?(Hash)
          value
        else
          # Convert to Parameters on first access
          self[key] = self.class.new(value)
        end
      end

      def each_element(object)
        if object.is_a?(Array)
          object.map { |el| yield el }.compact
        elsif object.is_a?(Hash) && object.keys.all? { |k| k =~ /\A-?\d+\z/ }
          hash = object.class.new
          object.each { |k,v| hash[k] = yield v }
          hash
        else
          yield object
        end
      end
  end

  module StrongParameters
    extend ActiveSupport::Concern
    include ActiveSupport::Rescuable

    included do
      rescue_from(ActionController::ParameterMissing) do |parameter_missing_exception|
        render text: "Required parameter missing: #{parameter_missing_exception.param}", status: :bad_request
      end
    end

    def params
      @_params ||= Parameters.new(request.parameters)
    end

    def params=(val)
      @_params = val.is_a?(Hash) ? Parameters.new(val) : val
    end
  end
end
