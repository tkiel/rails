require 'cases/helper'
require 'models/person'
require 'models/topic'

class NonExistentTable < ActiveRecord::Base; end

class CoreTest < ActiveRecord::TestCase
  fixtures :topics

  def test_inspect_class
    assert_equal 'ActiveRecord::Base', ActiveRecord::Base.inspect
    assert_equal 'LoosePerson(abstract)', LoosePerson.inspect
    assert_match(/^Topic\(id: integer, title: string/, Topic.inspect)
  end

  def test_inspect_instance
    topic = topics(:first)
    assert_equal %(#<Topic id: 1, title: "The First Topic", author_name: "David", author_email_address: "david@loudthinking.com", written_on: "#{topic.written_on.to_s(:db)}", bonus_time: "#{topic.bonus_time.to_s(:db)}", last_read: "#{topic.last_read.to_s(:db)}", content: "Have a nice day", important: nil, approved: false, replies_count: 1, unique_replies_count: 0, parent_id: nil, parent_title: nil, type: nil, group: nil, created_at: "#{topic.created_at.to_s(:db)}", updated_at: "#{topic.updated_at.to_s(:db)}">), topic.inspect
  end

  def test_inspect_new_instance
    assert_match(/Topic id: nil/, Topic.new.inspect)
  end

  def test_inspect_limited_select_instance
    assert_equal %(#<Topic id: 1>), Topic.all.merge!(:select => 'id', :where => 'id = 1').first.inspect
    assert_equal %(#<Topic id: 1, title: "The First Topic">), Topic.all.merge!(:select => 'id, title', :where => 'id = 1').first.inspect
  end

  def test_inspect_class_without_table
    assert_equal "NonExistentTable(Table doesn't exist)", NonExistentTable.inspect
  end
end
