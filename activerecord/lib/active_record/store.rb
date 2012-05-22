require 'active_support/core_ext/hash/indifferent_access'

module ActiveRecord
  # Store gives you a thin wrapper around serialize for the purpose of storing hashes in a single column.
  # It's like a simple key/value store backed into your record when you don't care about being able to
  # query that store outside the context of a single record.
  #
  # You can then declare accessors to this store that are then accessible just like any other attribute
  # of the model. This is very helpful for easily exposing store keys to a form or elsewhere that's
  # already built around just accessing attributes on the model.
  #
  # Make sure that you declare the database column used for the serialized store as a text, so there's
  # plenty of room.
  #
  # You can set custom coder to encode/decode your serialized attributes to/from different formats.
  # JSON, YAML, Marshal are supported out of the box. Generally it can be any wrapper that provides +load+ and +dump+.
  #
  # Examples:
  #
  #   class User < ActiveRecord::Base
  #     store :settings, accessors: [ :color, :homepage ], coder: JSON
  #   end
  #
  #   u = User.new(color: 'black', homepage: '37signals.com')
  #   u.color                          # Accessor stored attribute
  #   u.settings[:country] = 'Denmark' # Any attribute, even if not specified with an accessor
  #
  #   # There is no difference between strings and symbols for accessing custom attributes
  #   u.settings[:country]  # => 'Denmark'
  #   u.settings['country'] # => 'Denmark'
  #
  #   # Add additional accessors to an existing store through store_accessor
  #   class SuperUser < User
  #     store_accessor :settings, :privileges, :servants
  #   end
  module Store
    extend ActiveSupport::Concern

    module ClassMethods
      def store(store_attribute, options = {})
        serialize store_attribute, options.fetch(:coder, ActiveSupport::HashWithIndifferentAccess)
        store_accessor(store_attribute, options[:accessors]) if options.has_key? :accessors
      end

      def store_accessor(store_attribute, *keys)
        keys.flatten.each do |key|
          define_method("#{key}=") do |value|
            initialize_store_attribute(store_attribute)
            send(store_attribute)[key] = value
            send("#{store_attribute}_will_change!")
          end

          define_method(key) do
            initialize_store_attribute(store_attribute)
            send(store_attribute)[key]
          end
        end
      end
    end

    private
      def initialize_store_attribute(store_attribute)
        case attribute = send(store_attribute)
        when ActiveSupport::HashWithIndifferentAccess
          # Already initialized. Do nothing.
        when Hash
          # Initialized as a Hash. Convert to indifferent access.
          send :"#{store_attribute}=", attribute.with_indifferent_access
        else
          # Uninitialized. Set to an indifferent hash.
          send :"#{store_attribute}=", ActiveSupport::HashWithIndifferentAccess.new
        end
      end
  end
end
