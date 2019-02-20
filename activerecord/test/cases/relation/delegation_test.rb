# frozen_string_literal: true

require "cases/helper"
require "models/post"
require "models/comment"

module ActiveRecord
  module DelegationTests
    ARRAY_DELEGATES = [
      :+, :-, :|, :&, :[], :shuffle,
      :all?, :collect, :compact, :detect, :each, :each_cons, :each_with_index,
      :exclude?, :find_all, :flat_map, :group_by, :include?, :length,
      :map, :none?, :one?, :partition, :reject, :reverse, :rotate,
      :sample, :second, :sort, :sort_by, :slice, :third, :index, :rindex,
      :to_ary, :to_set, :to_xml, :to_yaml, :join,
      :in_groups, :in_groups_of, :to_sentence, :to_formatted_s, :as_json
    ]

    ARRAY_DELEGATES.each do |method|
      define_method "test_delegates_#{method}_to_Array" do
        assert_respond_to target, method
      end
    end

    def test_not_respond_to_arel_method
      assert_not_respond_to target, :exists
    end
  end

  class DelegationAssociationTest < ActiveRecord::TestCase
    include DelegationTests

    def target
      Post.new.comments
    end
  end

  class DelegationRelationTest < ActiveRecord::TestCase
    include DelegationTests

    def target
      Comment.all
    end
  end

  class QueryingMethodsDelegationTest < ActiveRecord::TestCase
    QUERYING_METHODS = [
      :find, :take, :take!, :first, :first!, :last, :last!, :exists?, :any?, :many?, :none?, :one?,
      :second, :second!, :third, :third!, :fourth, :fourth!, :fifth, :fifth!, :forty_two, :forty_two!, :third_to_last, :third_to_last!, :second_to_last, :second_to_last!,
      :first_or_create, :first_or_create!, :first_or_initialize,
      :find_or_create_by, :find_or_create_by!, :create_or_find_by, :create_or_find_by!, :find_or_initialize_by,
      :find_by, :find_by!,
      :destroy_all, :delete_all, :update_all, :delete_by, :destroy_by,
      :find_each, :find_in_batches, :in_batches,
      :select, :group, :order, :except, :reorder, :limit, :offset, :joins, :left_joins, :left_outer_joins, :or,
      :where, :rewhere, :preload, :eager_load, :includes, :from, :lock, :readonly, :extending,
      :having, :create_with, :distinct, :references, :none, :unscope, :merge,
      :count, :average, :minimum, :maximum, :sum, :calculate,
      :pluck, :pick, :ids,
    ]

    def test_delegate_querying_methods
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "posts"
      end

      QUERYING_METHODS.each do |method|
        assert_respond_to klass.all, method
        assert_respond_to klass, method
      end
    end
  end
end
