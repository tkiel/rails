require 'cases/helper'
require 'models/book'
require 'models/liquid'
require 'models/molecule'
require 'models/electron'

module ActiveRecord
  class StatementCacheTest < ActiveRecord::TestCase
    def setup
      skip if current_adapter?(:Mysql2Adapter)
      @connection = ActiveRecord::Base.connection
    end

    #Cache v 1.1 tests
    def test_statement_cache
      Book.create(name: "my book")
      Book.create(name: "my other book")

      cache = StatementCache.new do |params|
        Book.where(:name => params[:name])
      end

      b = cache.execute name: "my book"
      assert_equal "my book", b[0].name
      b = cache.execute name: "my other book"
      assert_equal "my other book", b[0].name
    end


    def test_statement_cache_id
      b1 = Book.create(name: "my book")
      b2 = Book.create(name: "my other book")

      cache = StatementCache.new do |params|
        Book.where(id: params[:id])
      end

      b = cache.execute id: b1.id
      assert_equal b1.name, b[0].name
      b = cache.execute id: b2.id
      assert_equal b2.name, b[0].name
    end

    def test_find_or_create_by
      Book.create(name: "my book")

      a = Book.find_or_create_by(name: "my book")
      b = Book.find_or_create_by(name: "my other book")

      assert_equal("my book", a.name)
      assert_equal("my other book", b.name)
    end

    #End

    def test_statement_cache_with_simple_statement
      cache = ActiveRecord::StatementCache.new do |params|
        Book.where(name: "my book").where("author_id > 3")
      end

      Book.create(name: "my book", author_id: 4)

      books = cache.execute({})
      assert_equal "my book", books[0].name
    end

    def test_statement_cache_with_complex_statement
      cache = ActiveRecord::StatementCache.new do |params|
        Liquid.joins(:molecules => :electrons).where('molecules.name' => 'dioxane', 'electrons.name' => 'lepton')
      end

      salty = Liquid.create(name: 'salty')
      molecule = salty.molecules.create(name: 'dioxane')
      molecule.electrons.create(name: 'lepton')

      liquids = cache.execute({})
      assert_equal "salty", liquids[0].name
    end

    def test_statement_cache_values_differ
      cache = ActiveRecord::StatementCache.new do |params|
        Book.where(name: "my book")
      end

      3.times do
        Book.create(name: "my book")
      end

      first_books = cache.execute({})

      3.times do
        Book.create(name: "my book")
      end

      additional_books = cache.execute({})
      assert first_books != additional_books
    end
  end
end
