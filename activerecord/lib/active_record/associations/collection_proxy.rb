module ActiveRecord
  module Associations
    # Association proxies in Active Record are middlemen between the object that
    # holds the association, known as the <tt>@owner</tt>, and the actual associated
    # object, known as the <tt>@target</tt>. The kind of association any proxy is
    # about is available in <tt>@reflection</tt>. That's an instance of the class
    # ActiveRecord::Reflection::AssociationReflection.
    #
    # For example, given
    #
    #   class Blog < ActiveRecord::Base
    #     has_many :posts
    #   end
    #
    #   blog = Blog.first
    #
    # the association proxy in <tt>blog.posts</tt> has the object in +blog+ as
    # <tt>@owner</tt>, the collection of its posts as <tt>@target</tt>, and
    # the <tt>@reflection</tt> object represents a <tt>:has_many</tt> macro.
    #
    # This class has most of the basic instance methods removed, and delegates
    # unknown methods to <tt>@target</tt> via <tt>method_missing</tt>. As a
    # corner case, it even removes the +class+ method and that's why you get
    #
    #   blog.posts.class # => Array
    #
    # though the object behind <tt>blog.posts</tt> is not an Array, but an
    # ActiveRecord::Associations::HasManyAssociation.
    #
    # The <tt>@target</tt> object is not \loaded until needed. For example,
    #
    #   blog.posts.count
    #
    # is computed directly through SQL and does not trigger by itself the
    # instantiation of the actual post records.
    class CollectionProxy < Relation
      delegate :target, :load_target, :loaded?, :to => :@association

      ##
      # :method: concat
      # Add +records+ to this association. Returns +self+ so method calls may
      # be chained. Since << flattens its argument list and inserts each record,
      # +push+ and +concat+ behave identically.
      #
      #   class Person < ActiveRecord::Base
      #     pets :has_many
      #   end
      #
      #   person.pets << Person.new(name: 'Nemo')
      #   person.pets.concat(Person.new(name: 'Droopy'))
      #   person.pets.push(Person.new(name: 'Ren'))
      #
      #   person.pets # => [#<Pet name: "Nemo">, #<Pet name: "Droopy">, #<Pet name: "Ren">]
      
      ##
      # :method: replace
      # Replace this collection with +other_array+. This will perform a diff
      # and delete/add only records that have changed.
      #
      #   class Person < ActiveRecord::Base
      #     has_many :pets
      #   end
      #
      #   person.pets
      #   # => [#<Pet id: 1, name: "Wy", group: "cats", person_id: 1>]
      #
      #   other_pets = [Pet.new(name: 'GorbyPuff', group: 'celebrities']
      #
      #   person.pets.replace(other_pets)
      #
      #   person.pets
      #   # => [#<Pet id: 2, name: "GorbyPuff", group: "celebrities", person_id: 1>]
      #
      # If the supplied array has an incorrect association type, it raises
      # an ActiveRecord::AssociationTypeMismatch error:
      #
      #   person.pets.replace(["doo", "ggie", "gaga"])
      #   # => ActiveRecord::AssociationTypeMismatch: Pet expected, got String

      ##
      # :method: destroy_all
      # Destroy all the records from this association.
      #
      #   class Person < ActiveRecord::Base
      #     has_many :pets
      #   end
      #
      #   person.pets.size # => 3
      #
      #   person.pets.destroy_all
      #
      #   person.pets.size # => 0
      #   person.pets      # => []
      
      ##
      # :method: empty?
      # Returns true if the collection is empty.
      # Equivalent to +size.zero?+.
      #
      #   class Person < ActiveRecord::Base
      #     has_many :pets
      #   end
      #
      #   person.pets.count  # => 1
      #   person.pets.empty? # => false 
      #
      #   person.pets.delete_all
      #   person.pets.count  # => 0
      #   person.pets.empty? # => true

      ##
      # :method: any?
      # Returns true if the collections is not empty.
      # Equivalent to +!collection.empty?+.
      #
      #   class Person < ActiveRecord::Base
      #     has_many :pets
      #   end
      #
      #   person.pets.count # => 0
      #   person.pets.any?  # => false
      #
      #   person.pets << Pet.new(name: 'Snoop')
      #   person.pets.count # => 0
      #   person.pets.any?  # => true
      #
      # Also, you can pass a block to define a criteria. The behaviour
      # is the same, it returns true if the collection based on the
      # criteria is not empty.
      #
      #   person.pets
      #   # => [#<Pet name: "Snoop", group: "dogs">]
      #
      #   person.pets.any? do |pet|
      #     pet.group == 'cats'
      #   end
      #   # => false
      #
      #   person.pets.any? do |pet|
      #     pet.group == 'dogs'
      #   end
      #   # => true

      ##
      # :method: many?
      # Returns true if the collection has more than 1 record.
      # Equivalent to +collection.size > 1+.
      #
      #   class Person < ActiveRecord::Base
      #     has_many :pets
      #   end
      #
      #   person.pets.count #=> 1
      #   person.pets.many? #=> false
      #
      #   person.pets << Pet.new(name: 'Snoopy')
      #   person.pets.count #=> 2
      #   person.pets.many? #=> true
      #
      # Also, you can pass a block to define a criteria. The
      # behaviour is the same, it returns true if the collection
      # based on the criteria has more than 1 record.
      #
      #   person.pets
      #   # => [
      #   #      #<Pet name: "GorbyPuff", group: "cats">,
      #   #      #<Pet name: "Wy", group: "cats">,
      #   #      #<Pet name: "Snoop", group: "dogs">
      #   #    ]
      #
      #   person.pets.many? do |pet|
      #     pet.group == 'dogs'
      #   end
      #   # => false
      #
      #   person.pets.many? do |pet|
      #     pet.group == 'cats'
      #   end
      #   # => true

      ##
      # :method: include?
      # Returns true if the given object is present in the collection.
      #
      #   class Person < ActiveRecord::Base
      #     has_many :pets
      #   end
      #
      #   person.pets # => [#<Pet id: 20, name: "Snoop">]
      #
      #   person.pets.include?(Pet.find(20)) # => true
      #   person.pets.include?(Pet.find(21)) # => false
      delegate :select, :find, :first, :last,
               :build, :create, :create!,
               :concat, :replace, :delete_all, :destroy_all, :delete, :destroy, :uniq,
               :sum, :count, :size, :length, :empty?,
               :any?, :many?, :include?,
               :to => :@association

      def initialize(association)
        @association = association
        super association.klass, association.klass.arel_table
        merge! association.scoped
      end

      alias_method :new, :build

      def proxy_association
        @association
      end

      # We don't want this object to be put on the scoping stack, because
      # that could create an infinite loop where we call an @association
      # method, which gets the current scope, which is this object, which
      # delegates to @association, and so on.
      def scoping
        @association.scoped.scoping { yield }
      end

      def spawn
        scoped
      end

      def scoped(options = nil)
        association = @association

        super.extending! do
          define_method(:proxy_association) { association }
        end
      end

      def ==(other)
        load_target == other
      end

      def to_ary
        load_target.dup
      end
      alias_method :to_a, :to_ary

      def <<(*records)
        proxy_association.concat(records) && self
      end
      alias_method :push, :<<

      def clear
        delete_all
        self
      end

      def reload
        proxy_association.reload
        self
      end
    end
  end
end
