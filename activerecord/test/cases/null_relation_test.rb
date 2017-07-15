require "cases/helper"
require "models/aircraft"
require "models/engine"
require "models/developer"
require "models/comment"
require "models/post"
require "models/topic"

class NullRelationTest < ActiveRecord::TestCase
  fixtures :posts, :comments

  def test_none
    assert_no_queries(ignore_none: false) do
      assert_equal [], Developer.none
      assert_equal [], Developer.all.none
    end
  end

  def test_none_chainable
    assert_no_queries(ignore_none: false) do
      assert_equal [], Developer.none.where(name: "David")
    end
  end

  def test_none_chainable_to_existing_scope_extension_method
    assert_no_queries(ignore_none: false) do
      assert_equal 1, Topic.anonymous_extension.none.one
    end
  end

  def test_none_chained_to_methods_firing_queries_straight_to_db
    assert_no_queries(ignore_none: false) do
      assert_equal [],    Developer.none.pluck(:id, :name)
      assert_equal 0,     Developer.none.delete_all
      assert_equal 0,     Developer.none.update_all(name: "David")
      assert_equal 0,     Developer.none.delete(1)
      assert_equal false, Developer.none.exists?(1)
    end
  end

  def test_null_relation_content_size_methods
    assert_no_queries(ignore_none: false) do
      assert_equal 0,     Developer.none.size
      assert_equal 0,     Developer.none.count
      assert_equal true,  Developer.none.empty?
      assert_equal true,  Developer.none.none?
      assert_equal false, Developer.none.any?
      assert_equal false, Developer.none.one?
      assert_equal false, Developer.none.many?
    end
  end

  def test_null_relation_calculations_methods
    assert_no_queries(ignore_none: false) do
      assert_equal 0, Developer.none.count
      assert_equal 0, Developer.none.calculate(:count, nil)
      assert_nil Developer.none.calculate(:average, "salary")
    end
  end

  def test_null_relation_metadata_methods
    assert_equal "", Developer.none.to_sql
    assert_equal({}, Developer.none.where_values_hash)
  end

  def test_null_relation_where_values_hash
    assert_equal({ "salary" => 100_000 }, Developer.none.where(salary: 100_000).where_values_hash)
  end

  def test_null_relation_sum
    ac = Aircraft.new
    assert_equal Hash.new, ac.engines.group(:id).sum(:id)
    assert_equal 0, ac.engines.count
    ac.save
    assert_equal Hash.new, ac.engines.group(:id).sum(:id)
    assert_equal 0, ac.engines.count
  end

  def test_null_relation_count
    ac = Aircraft.new
    assert_equal Hash.new, ac.engines.group(:id).count
    assert_equal 0, ac.engines.count
    ac.save
    assert_equal Hash.new, ac.engines.group(:id).count
    assert_equal 0, ac.engines.count
  end

  def test_null_relation_size
    ac = Aircraft.new
    assert_equal Hash.new, ac.engines.group(:id).size
    assert_equal 0, ac.engines.size
    ac.save
    assert_equal Hash.new, ac.engines.group(:id).size
    assert_equal 0, ac.engines.size
  end

  def test_null_relation_average
    ac = Aircraft.new
    assert_equal Hash.new, ac.engines.group(:car_id).average(:id)
    assert_nil ac.engines.average(:id)
    ac.save
    assert_equal Hash.new, ac.engines.group(:car_id).average(:id)
    assert_nil ac.engines.average(:id)
  end

  def test_null_relation_minimum
    ac = Aircraft.new
    assert_equal Hash.new, ac.engines.group(:car_id).minimum(:id)
    assert_nil ac.engines.minimum(:id)
    ac.save
    assert_equal Hash.new, ac.engines.group(:car_id).minimum(:id)
    assert_nil ac.engines.minimum(:id)
  end

  def test_null_relation_maximum
    ac = Aircraft.new
    assert_equal Hash.new, ac.engines.group(:car_id).maximum(:id)
    assert_nil ac.engines.maximum(:id)
    ac.save
    assert_equal Hash.new, ac.engines.group(:car_id).maximum(:id)
    assert_nil ac.engines.maximum(:id)
  end

  def test_null_relation_in_where_condition
    assert_operator Comment.count, :>, 0 # precondition, make sure there are comments.
    assert_equal 0, Comment.where(post_id: Post.none).count
  end
end
