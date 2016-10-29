require "cases/helper"
require "models/aircraft"
require "models/post"
require "models/comment"
require "models/author"
require "models/topic"
require "models/reply"
require "models/category"
require "models/company"
require "models/developer"
require "models/computer"
require "models/project"
require "models/minimalistic"
require "models/warehouse_thing"
require "models/parrot"
require "models/minivan"
require "models/owner"
require "models/person"
require "models/pet"
require "models/ship"
require "models/toy"
require "models/admin"
require "models/admin/user"
require "rexml/document"

class PersistenceTest < ActiveRecord::TestCase
  fixtures :topics, :companies, :developers, :projects, :computers, :accounts, :minimalistics, "warehouse-things", :authors, :author_addresses, :categorizations, :categories, :posts, :minivans, :pets, :toys

  # Oracle UPDATE does not support ORDER BY
  unless current_adapter?(:OracleAdapter)
    def test_update_all_ignores_order_without_limit_from_association
      author = authors(:david)
      assert_nothing_raised do
        assert_equal author.posts_with_comments_and_categories.length, author.posts_with_comments_and_categories.update_all([ "body = ?", "bulk update!" ])
      end
    end

    def test_update_all_doesnt_ignore_order
      assert_equal authors(:david).id + 1, authors(:mary).id # make sure there is going to be a duplicate PK error
      test_update_with_order_succeeds = lambda do |order|
        begin
          Author.order(order).update_all("id = id + 1")
        rescue ActiveRecord::ActiveRecordError
          false
        end
      end

      if test_update_with_order_succeeds.call("id DESC")
        assert !test_update_with_order_succeeds.call("id ASC") # test that this wasn't a fluke and using an incorrect order results in an exception
      else
        # test that we're failing because the current Arel's engine doesn't support UPDATE ORDER BY queries is using subselects instead
        assert_sql(/\AUPDATE .+ \(SELECT .* ORDER BY id DESC\)\Z/i) do
          test_update_with_order_succeeds.call("id DESC")
        end
      end
    end

    def test_update_all_with_order_and_limit_updates_subset_only
      author = authors(:david)
      assert_nothing_raised do
        assert_equal 1, author.posts_sorted_by_id_limited.size
        assert_equal 2, author.posts_sorted_by_id_limited.limit(2).to_a.size
        assert_equal 1, author.posts_sorted_by_id_limited.update_all([ "body = ?", "bulk update!" ])
        assert_equal "bulk update!", posts(:welcome).body
        assert_not_equal "bulk update!", posts(:thinking).body
      end
    end
  end

  def test_update_many
    topic_data = { 1 => { "content" => "1 updated" }, 2 => { "content" => "2 updated" } }
    updated = Topic.update(topic_data.keys, topic_data.values)

    assert_equal 2, updated.size
    assert_equal "1 updated", Topic.find(1).content
    assert_equal "2 updated", Topic.find(2).content
  end

  def test_delete_all
    assert Topic.count > 0

    assert_equal Topic.count, Topic.delete_all
  end

  def test_delete_all_with_joins_and_where_part_is_hash
    where_args = { toys: { name: "Bone" } }
    count = Pet.joins(:toys).where(where_args).count

    assert_equal count, 1
    assert_equal count, Pet.joins(:toys).where(where_args).delete_all
  end

  def test_delete_all_with_joins_and_where_part_is_not_hash
    where_args = ["toys.name = ?", "Bone"]
    count = Pet.joins(:toys).where(where_args).count

    assert_equal count, 1
    assert_equal count, Pet.joins(:toys).where(where_args).delete_all
  end

  def test_increment_attribute
    assert_equal 50, accounts(:signals37).credit_limit
    accounts(:signals37).increment! :credit_limit
    assert_equal 51, accounts(:signals37, :reload).credit_limit

    accounts(:signals37).increment(:credit_limit).increment!(:credit_limit)
    assert_equal 53, accounts(:signals37, :reload).credit_limit
  end

  def test_increment_nil_attribute
    assert_nil topics(:first).parent_id
    topics(:first).increment! :parent_id
    assert_equal 1, topics(:first).parent_id
  end

  def test_increment_attribute_by
    assert_equal 50, accounts(:signals37).credit_limit
    accounts(:signals37).increment! :credit_limit, 5
    assert_equal 55, accounts(:signals37, :reload).credit_limit

    accounts(:signals37).increment(:credit_limit, 1).increment!(:credit_limit, 3)
    assert_equal 59, accounts(:signals37, :reload).credit_limit
  end

  def test_increment_updates_counter_in_db_using_offset
    a1 = accounts(:signals37)
    initial_credit = a1.credit_limit
    a2 = Account.find(accounts(:signals37).id)
    a1.increment!(:credit_limit)
    a2.increment!(:credit_limit)
    assert_equal initial_credit + 2, a1.reload.credit_limit
  end

  def test_destroy_all
    conditions = "author_name = 'Mary'"
    topics_by_mary = Topic.all.merge!(where: conditions, order: "id").to_a
    assert ! topics_by_mary.empty?

    assert_difference("Topic.count", -topics_by_mary.size) do
      destroyed = Topic.where(conditions).destroy_all.sort_by(&:id)
      assert_equal topics_by_mary, destroyed
      assert destroyed.all?(&:frozen?), "destroyed topics should be frozen"
    end
  end

  def test_destroy_many
    clients = Client.all.merge!(order: "id").find([2, 3])

    assert_difference("Client.count", -2) do
      destroyed = Client.destroy([2, 3]).sort_by(&:id)
      assert_equal clients, destroyed
      assert destroyed.all?(&:frozen?), "destroyed clients should be frozen"
    end
  end

  def test_becomes
    assert_kind_of Reply, topics(:first).becomes(Reply)
    assert_equal "The First Topic", topics(:first).becomes(Reply).title
  end

  def test_becomes_includes_errors
    company = Company.new(name: nil)
    assert !company.valid?
    original_errors = company.errors
    client = company.becomes(Client)
    assert_equal original_errors.keys, client.errors.keys
  end

  def test_becomes_errors_base
    child_class = Class.new(Admin::User) do
      store_accessor :settings, :foo

      def self.name; "Admin::ChildUser"; end
    end

    admin = Admin::User.new
    admin.errors.add :token, :invalid
    child = admin.becomes(child_class)

    assert_equal [:token], child.errors.keys
    assert_nothing_raised do
      child.errors.add :foo, :invalid
    end
  end

  def test_duped_becomes_persists_changes_from_the_original
    original = topics(:first)
    copy = original.dup.becomes(Reply)
    copy.save!
    assert_equal "The First Topic", Topic.find(copy.id).title
  end

  def test_becomes_includes_changed_attributes
    company = Company.new(name: "37signals")
    client = company.becomes(Client)
    assert_equal "37signals", client.name
    assert_equal %w{name}, client.changed
  end

  def test_delete_many
    original_count = Topic.count
    Topic.delete(deleting = [1, 2])
    assert_equal original_count - deleting.size, Topic.count
  end

  def test_decrement_attribute
    assert_equal 50, accounts(:signals37).credit_limit

    accounts(:signals37).decrement!(:credit_limit)
    assert_equal 49, accounts(:signals37, :reload).credit_limit

    accounts(:signals37).decrement(:credit_limit).decrement!(:credit_limit)
    assert_equal 47, accounts(:signals37, :reload).credit_limit
  end

  def test_decrement_attribute_by
    assert_equal 50, accounts(:signals37).credit_limit
    accounts(:signals37).decrement! :credit_limit, 5
    assert_equal 45, accounts(:signals37, :reload).credit_limit

    accounts(:signals37).decrement(:credit_limit, 1).decrement!(:credit_limit, 3)
    assert_equal 41, accounts(:signals37, :reload).credit_limit
  end

  def test_create
    topic = Topic.new
    topic.title = "New Topic"
    topic.save
    topic_reloaded = Topic.find(topic.id)
    assert_equal("New Topic", topic_reloaded.title)
  end

  def test_save!
    topic = Topic.new(title: "New Topic")
    assert topic.save!

    reply = WrongReply.new
    assert_raise(ActiveRecord::RecordInvalid) { reply.save! }
  end

  def test_save_null_string_attributes
    topic = Topic.find(1)
    topic.attributes = { "title" => "null", "author_name" => "null" }
    topic.save!
    topic.reload
    assert_equal("null", topic.title)
    assert_equal("null", topic.author_name)
  end

  def test_save_nil_string_attributes
    topic = Topic.find(1)
    topic.title = nil
    topic.save!
    topic.reload
    assert_nil topic.title
  end

  def test_save_for_record_with_only_primary_key
    minimalistic = Minimalistic.new
    assert_nothing_raised { minimalistic.save }
  end

  def test_save_for_record_with_only_primary_key_that_is_provided
    assert_nothing_raised { Minimalistic.create!(id: 2) }
  end

  def test_save_with_duping_of_destroyed_object
    developer = Developer.first
    developer.destroy
    new_developer = developer.dup
    new_developer.save
    assert new_developer.persisted?
    assert_not new_developer.destroyed?
  end

  def test_create_many
    topics = Topic.create([ { "title" => "first" }, { "title" => "second" }])
    assert_equal 2, topics.size
    assert_equal "first", topics.first.title
  end

  def test_create_columns_not_equal_attributes
    topic = Topic.instantiate(
      "attributes" => {
        "title"          => "Another New Topic",
        "does_not_exist" => "test"
      }
    )
    assert_nothing_raised { topic.save }
  end

  def test_create_through_factory_with_block
    topic = Topic.create("title" => "New Topic") do |t|
      t.author_name = "David"
    end
    assert_equal("New Topic", topic.title)
    assert_equal("David", topic.author_name)
  end

  def test_create_many_through_factory_with_block
    topics = Topic.create([ { "title" => "first" }, { "title" => "second" }]) do |t|
      t.author_name = "David"
    end
    assert_equal 2, topics.size
    topic1, topic2 = Topic.find(topics[0].id), Topic.find(topics[1].id)
    assert_equal "first", topic1.title
    assert_equal "David", topic1.author_name
    assert_equal "second", topic2.title
    assert_equal "David", topic2.author_name
  end

  def test_update_object
    topic = Topic.new
    topic.title = "Another New Topic"
    topic.written_on = "2003-12-12 23:23:00"
    topic.save
    topic_reloaded = Topic.find(topic.id)
    assert_equal("Another New Topic", topic_reloaded.title)

    topic_reloaded.title = "Updated topic"
    topic_reloaded.save

    topic_reloaded_again = Topic.find(topic.id)

    assert_equal("Updated topic", topic_reloaded_again.title)
  end

  def test_update_columns_not_equal_attributes
    topic = Topic.new
    topic.title = "Still another topic"
    topic.save

    topic_reloaded = Topic.instantiate(topic.attributes.merge("does_not_exist" => "test"))
    topic_reloaded.title = "A New Topic"
    assert_nothing_raised { topic_reloaded.save }
  end

  def test_update_for_record_with_only_primary_key
    minimalistic = minimalistics(:first)
    assert_nothing_raised { minimalistic.save }
  end

  def test_update_sti_type
    assert_instance_of Reply, topics(:second)

    topic = topics(:second).becomes!(Topic)
    assert_instance_of Topic, topic
    topic.save!
    assert_instance_of Topic, Topic.find(topic.id)
  end

  def test_preserve_original_sti_type
    reply = topics(:second)
    assert_equal "Reply", reply.type

    topic = reply.becomes(Topic)
    assert_equal "Reply", reply.type

    assert_instance_of Topic, topic
    assert_equal "Reply", topic.type
  end

  def test_update_sti_subclass_type
    assert_instance_of Topic, topics(:first)

    reply = topics(:first).becomes!(Reply)
    assert_instance_of Reply, reply
    reply.save!
    assert_instance_of Reply, Reply.find(reply.id)
  end

  def test_update_after_create
    klass = Class.new(Topic) do
      def self.name; "Topic"; end
      after_create do
        update_attribute("author_name", "David")
      end
    end
    topic = klass.new
    topic.title = "Another New Topic"
    topic.save

    topic_reloaded = Topic.find(topic.id)
    assert_equal("Another New Topic", topic_reloaded.title)
    assert_equal("David", topic_reloaded.author_name)
  end

  def test_update_attribute_does_not_run_sql_if_attribute_is_not_changed
    klass = Class.new(Topic) do
      def self.name; "Topic"; end
    end
    topic = klass.create(title: "Another New Topic")
    assert_queries(0) do
      assert topic.update_attribute(:title, "Another New Topic")
    end
  end

  def test_update_does_not_run_sql_if_record_has_not_changed
    topic = Topic.create(title: "Another New Topic")
    assert_queries(0) { assert topic.update(title: "Another New Topic") }
    assert_queries(0) { assert topic.update_attributes(title: "Another New Topic") }
  end

  def test_delete
    topic = Topic.find(1)
    assert_equal topic, topic.delete, "topic.delete did not return self"
    assert topic.frozen?, "topic not frozen after delete"
    assert_raise(ActiveRecord::RecordNotFound) { Topic.find(topic.id) }
  end

  def test_delete_doesnt_run_callbacks
    Topic.find(1).delete
    assert_not_nil Topic.find(2)
  end

  def test_destroy
    topic = Topic.find(1)
    assert_equal topic, topic.destroy, "topic.destroy did not return self"
    assert topic.frozen?, "topic not frozen after destroy"
    assert_raise(ActiveRecord::RecordNotFound) { Topic.find(topic.id) }
  end

  def test_destroy!
    topic = Topic.find(1)
    assert_equal topic, topic.destroy!, "topic.destroy! did not return self"
    assert topic.frozen?, "topic not frozen after destroy!"
    assert_raise(ActiveRecord::RecordNotFound) { Topic.find(topic.id) }
  end

  def test_record_not_found_exception
    assert_raise(ActiveRecord::RecordNotFound) { Topic.find(99999) }
  end

  def test_update_all
    assert_equal Topic.count, Topic.update_all("content = 'bulk updated!'")
    assert_equal "bulk updated!", Topic.find(1).content
    assert_equal "bulk updated!", Topic.find(2).content

    assert_equal Topic.count, Topic.update_all(["content = ?", "bulk updated again!"])
    assert_equal "bulk updated again!", Topic.find(1).content
    assert_equal "bulk updated again!", Topic.find(2).content

    assert_equal Topic.count, Topic.update_all(["content = ?", nil])
    assert_nil Topic.find(1).content
  end

  def test_update_all_with_hash
    assert_not_nil Topic.find(1).last_read
    assert_equal Topic.count, Topic.update_all(content: "bulk updated with hash!", last_read: nil)
    assert_equal "bulk updated with hash!", Topic.find(1).content
    assert_equal "bulk updated with hash!", Topic.find(2).content
    assert_nil Topic.find(1).last_read
    assert_nil Topic.find(2).last_read
  end

  def test_update_all_with_non_standard_table_name
    assert_equal 1, WarehouseThing.where(id: 1).update_all(["value = ?", 0])
    assert_equal 0, WarehouseThing.find(1).value
  end

  def test_delete_new_record
    client = Client.new
    client.delete
    assert client.frozen?
  end

  def test_delete_record_with_associations
    client = Client.find(3)
    client.delete
    assert client.frozen?
    assert_kind_of Firm, client.firm
    assert_raise(RuntimeError) { client.name = "something else" }
  end

  def test_destroy_new_record
    client = Client.new
    client.destroy
    assert client.frozen?
  end

  def test_destroy_record_with_associations
    client = Client.find(3)
    client.destroy
    assert client.frozen?
    assert_kind_of Firm, client.firm
    assert_raise(RuntimeError) { client.name = "something else" }
  end

  def test_update_attribute
    assert !Topic.find(1).approved?
    Topic.find(1).update_attribute("approved", true)
    assert Topic.find(1).approved?

    Topic.find(1).update_attribute(:approved, false)
    assert !Topic.find(1).approved?
  end

  def test_update_attribute_for_readonly_attribute
    minivan = Minivan.find("m1")
    assert_raises(ActiveRecord::ActiveRecordError) { minivan.update_attribute(:color, "black") }
  end

  def test_update_attribute_with_one_updated
    t = Topic.first
    t.update_attribute(:title, "super_title")
    assert_equal "super_title", t.title
    assert !t.changed?, "topic should not have changed"
    assert !t.title_changed?, "title should not have changed"
    assert_nil t.title_change, "title change should be nil"

    t.reload
    assert_equal "super_title", t.title
  end

  def test_update_attribute_for_updated_at_on
    developer = Developer.find(1)
    prev_month = Time.now.prev_month.change(usec: 0)

    developer.update_attribute(:updated_at, prev_month)
    assert_equal prev_month, developer.updated_at

    developer.update_attribute(:salary, 80001)
    assert_not_equal prev_month, developer.updated_at

    developer.reload
    assert_not_equal prev_month, developer.updated_at
  end

  def test_update_column
    topic = Topic.find(1)
    topic.update_column("approved", true)
    assert topic.approved?
    topic.reload
    assert topic.approved?

    topic.update_column(:approved, false)
    assert !topic.approved?
    topic.reload
    assert !topic.approved?
  end

  def test_update_column_should_not_use_setter_method
    dev = Developer.find(1)
    dev.instance_eval { def salary=(value); write_attribute(:salary, value * 2); end }

    dev.update_column(:salary, 80000)
    assert_equal 80000, dev.salary

    dev.reload
    assert_equal 80000, dev.salary
  end

  def test_update_column_should_raise_exception_if_new_record
    topic = Topic.new
    assert_raises(ActiveRecord::ActiveRecordError) { topic.update_column("approved", false) }
  end

  def test_update_column_should_not_leave_the_object_dirty
    topic = Topic.find(1)
    topic.update_column("content", "--- Have a nice day\n...\n")

    topic.reload
    topic.update_column(:content, "--- You too\n...\n")
    assert_equal [], topic.changed

    topic.reload
    topic.update_column("content", "--- Have a nice day\n...\n")
    assert_equal [], topic.changed
  end

  def test_update_column_with_model_having_primary_key_other_than_id
    minivan = Minivan.find("m1")
    new_name = "sebavan"

    minivan.update_column(:name, new_name)
    assert_equal new_name, minivan.name
  end

  def test_update_column_for_readonly_attribute
    minivan = Minivan.find("m1")
    prev_color = minivan.color
    assert_raises(ActiveRecord::ActiveRecordError) { minivan.update_column(:color, "black") }
    assert_equal prev_color, minivan.color
  end

  def test_update_column_should_not_modify_updated_at
    developer = Developer.find(1)
    prev_month = Time.now.prev_month.change(usec: 0)

    developer.update_column(:updated_at, prev_month)
    assert_equal prev_month, developer.updated_at

    developer.update_column(:salary, 80001)
    assert_equal prev_month, developer.updated_at

    developer.reload
    assert_equal prev_month.to_i, developer.updated_at.to_i
  end

  def test_update_column_with_one_changed_and_one_updated
    t = Topic.order("id").limit(1).first
    author_name = t.author_name
    t.author_name = "John"
    t.update_column(:title, "super_title")
    assert_equal "John", t.author_name
    assert_equal "super_title", t.title
    assert t.changed?, "topic should have changed"
    assert t.author_name_changed?, "author_name should have changed"

    t.reload
    assert_equal author_name, t.author_name
    assert_equal "super_title", t.title
  end

  def test_update_column_with_default_scope
    developer = DeveloperCalledDavid.first
    developer.name = "John"
    developer.save!

    assert developer.update_column(:name, "Will"), "did not update record due to default scope"
  end

  def test_update_columns
    topic = Topic.find(1)
    topic.update_columns("approved" => true, title: "Sebastian Topic")
    assert topic.approved?
    assert_equal "Sebastian Topic", topic.title
    topic.reload
    assert topic.approved?
    assert_equal "Sebastian Topic", topic.title
  end

  def test_update_columns_should_not_use_setter_method
    dev = Developer.find(1)
    dev.instance_eval { def salary=(value); write_attribute(:salary, value * 2); end }

    dev.update_columns(salary: 80000)
    assert_equal 80000, dev.salary

    dev.reload
    assert_equal 80000, dev.salary
  end

  def test_update_columns_should_raise_exception_if_new_record
    topic = Topic.new
    assert_raises(ActiveRecord::ActiveRecordError) { topic.update_columns(approved: false) }
  end

  def test_update_columns_should_not_leave_the_object_dirty
    topic = Topic.find(1)
    topic.update("content" => "--- Have a nice day\n...\n", :author_name => "Jose")

    topic.reload
    topic.update_columns(content: "--- You too\n...\n", "author_name" => "Sebastian")
    assert_equal [], topic.changed

    topic.reload
    topic.update_columns(content: "--- Have a nice day\n...\n", author_name: "Jose")
    assert_equal [], topic.changed
  end

  def test_update_columns_with_model_having_primary_key_other_than_id
    minivan = Minivan.find("m1")
    new_name = "sebavan"

    minivan.update_columns(name: new_name)
    assert_equal new_name, minivan.name
  end

  def test_update_columns_with_one_readonly_attribute
    minivan = Minivan.find("m1")
    prev_color = minivan.color
    prev_name = minivan.name
    assert_raises(ActiveRecord::ActiveRecordError) { minivan.update_columns(name: "My old minivan", color: "black") }
    assert_equal prev_color, minivan.color
    assert_equal prev_name, minivan.name

    minivan.reload
    assert_equal prev_color, minivan.color
    assert_equal prev_name, minivan.name
  end

  def test_update_columns_should_not_modify_updated_at
    developer = Developer.find(1)
    prev_month = Time.now.prev_month.change(usec: 0)

    developer.update_columns(updated_at: prev_month)
    assert_equal prev_month, developer.updated_at

    developer.update_columns(salary: 80000)
    assert_equal prev_month, developer.updated_at
    assert_equal 80000, developer.salary

    developer.reload
    assert_equal prev_month.to_i, developer.updated_at.to_i
    assert_equal 80000, developer.salary
  end

  def test_update_columns_with_one_changed_and_one_updated
    t = Topic.order("id").limit(1).first
    author_name = t.author_name
    t.author_name = "John"
    t.update_columns(title: "super_title")
    assert_equal "John", t.author_name
    assert_equal "super_title", t.title
    assert t.changed?, "topic should have changed"
    assert t.author_name_changed?, "author_name should have changed"

    t.reload
    assert_equal author_name, t.author_name
    assert_equal "super_title", t.title
  end

  def test_update_columns_changing_id
    topic = Topic.find(1)
    topic.update_columns(id: 123)
    assert_equal 123, topic.id
    topic.reload
    assert_equal 123, topic.id
  end

  def test_update_columns_returns_boolean
    topic = Topic.find(1)
    assert_equal true, topic.update_columns(title: "New title")
  end

  def test_update_columns_with_default_scope
    developer = DeveloperCalledDavid.first
    developer.name = "John"
    developer.save!

    assert developer.update_columns(name: "Will"), "did not update record due to default scope"
  end

  def test_update
    topic = Topic.find(1)
    assert !topic.approved?
    assert_equal "The First Topic", topic.title

    topic.update("approved" => true, "title" => "The First Topic Updated")
    topic.reload
    assert topic.approved?
    assert_equal "The First Topic Updated", topic.title

    topic.update(approved: false, title: "The First Topic")
    topic.reload
    assert !topic.approved?
    assert_equal "The First Topic", topic.title
  end

  def test_update_attributes
    topic = Topic.find(1)
    assert !topic.approved?
    assert_equal "The First Topic", topic.title

    topic.update_attributes("approved" => true, "title" => "The First Topic Updated")
    topic.reload
    assert topic.approved?
    assert_equal "The First Topic Updated", topic.title

    topic.update_attributes(approved: false, title: "The First Topic")
    topic.reload
    assert !topic.approved?
    assert_equal "The First Topic", topic.title

    error = assert_raise(ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid) do
      topic.update_attributes(id: 3, title: "Hm is it possible?")
    end
    assert_not_nil error.cause
    assert_not_equal "Hm is it possible?", Topic.find(3).title

    topic.update_attributes(id: 1234)
    assert_nothing_raised { topic.reload }
    assert_equal topic.title, Topic.find(1234).title
  end

  def test_update_attributes_parameters
    topic = Topic.find(1)
    assert_nothing_raised do
      topic.update_attributes({})
    end

    assert_raises(ArgumentError) do
      topic.update_attributes(nil)
    end
  end

  def test_update!
    Reply.validates_presence_of(:title)
    reply = Reply.find(2)
    assert_equal "The Second Topic of the day", reply.title
    assert_equal "Have a nice day", reply.content

    reply.update!("title" => "The Second Topic of the day updated", "content" => "Have a nice evening")
    reply.reload
    assert_equal "The Second Topic of the day updated", reply.title
    assert_equal "Have a nice evening", reply.content

    reply.update!(title: "The Second Topic of the day", content: "Have a nice day")
    reply.reload
    assert_equal "The Second Topic of the day", reply.title
    assert_equal "Have a nice day", reply.content

    assert_raise(ActiveRecord::RecordInvalid) { reply.update!(title: nil, content: "Have a nice evening") }
  ensure
    Reply.clear_validators!
  end

  def test_update_attributes!
    Reply.validates_presence_of(:title)
    reply = Reply.find(2)
    assert_equal "The Second Topic of the day", reply.title
    assert_equal "Have a nice day", reply.content

    reply.update_attributes!("title" => "The Second Topic of the day updated", "content" => "Have a nice evening")
    reply.reload
    assert_equal "The Second Topic of the day updated", reply.title
    assert_equal "Have a nice evening", reply.content

    reply.update_attributes!(title: "The Second Topic of the day", content: "Have a nice day")
    reply.reload
    assert_equal "The Second Topic of the day", reply.title
    assert_equal "Have a nice day", reply.content

    assert_raise(ActiveRecord::RecordInvalid) { reply.update_attributes!(title: nil, content: "Have a nice evening") }
  ensure
    Reply.clear_validators!
  end

  def test_destroyed_returns_boolean
    developer = Developer.first
    assert_equal false, developer.destroyed?
    developer.destroy
    assert_equal true, developer.destroyed?

    developer = Developer.last
    assert_equal false, developer.destroyed?
    developer.delete
    assert_equal true, developer.destroyed?
  end

  def test_persisted_returns_boolean
    developer = Developer.new(name: "Jose")
    assert_equal false, developer.persisted?
    developer.save!
    assert_equal true, developer.persisted?

    developer = Developer.first
    assert_equal true, developer.persisted?
    developer.destroy
    assert_equal false, developer.persisted?

    developer = Developer.last
    assert_equal true, developer.persisted?
    developer.delete
    assert_equal false, developer.persisted?
  end

  def test_class_level_destroy
    should_be_destroyed_reply = Reply.create("title" => "hello", "content" => "world")
    Topic.find(1).replies << should_be_destroyed_reply

    Topic.destroy(1)
    assert_raise(ActiveRecord::RecordNotFound) { Topic.find(1) }
    assert_raise(ActiveRecord::RecordNotFound) { Reply.find(should_be_destroyed_reply.id) }
  end

  def test_class_level_delete
    should_be_destroyed_reply = Reply.create("title" => "hello", "content" => "world")
    Topic.find(1).replies << should_be_destroyed_reply

    Topic.delete(1)
    assert_raise(ActiveRecord::RecordNotFound) { Topic.find(1) }
    assert_nothing_raised { Reply.find(should_be_destroyed_reply.id) }
  end

  def test_create_with_custom_timestamps
    custom_datetime = 1.hour.ago.beginning_of_day

    %w(created_at created_on updated_at updated_on).each do |attribute|
      parrot = LiveParrot.create(:name => "colombian", attribute => custom_datetime)
      assert_equal custom_datetime, parrot[attribute]
    end
  end

  def test_persist_inherited_class_with_different_table_name
    minimalistic_aircrafts = Class.new(Minimalistic) do
      self.table_name = "aircraft"
    end

    assert_difference "Aircraft.count", 1 do
      aircraft = minimalistic_aircrafts.create(name: "Wright Flyer")
      aircraft.name = "Wright Glider"
      aircraft.save
    end

    assert_equal "Wright Glider", Aircraft.last.name
  end

  def test_instantiate_creates_a_new_instance
    post = Post.instantiate("title" => "appropriate documentation", "type" => "SpecialPost")
    assert_equal "appropriate documentation", post.title
    assert_instance_of SpecialPost, post

    # body was not initialized
    assert_raises ActiveModel::MissingAttributeError do
      post.body
    end
  end

  def test_reload_removes_custom_selects
    post = Post.select("posts.*, 1 as wibble").last!

    assert_equal 1, post[:wibble]
    assert_nil post.reload[:wibble]
  end

  def test_find_via_reload
    post = Post.new

    assert post.new_record?

    post.id = 1
    post.reload

    assert_equal "Welcome to the weblog", post.title
    assert_not post.new_record?
  end

  def test_reload_via_querycache
    ActiveRecord::Base.connection.enable_query_cache!
    ActiveRecord::Base.connection.clear_query_cache
    assert ActiveRecord::Base.connection.query_cache_enabled, "cache should be on"
    parrot = Parrot.create(name: "Shane")

    # populate the cache with the SELECT result
    found_parrot = Parrot.find(parrot.id)
    assert_equal parrot.id, found_parrot.id

    # Manually update the 'name' attribute in the DB directly
    assert_equal 1, ActiveRecord::Base.connection.query_cache.length
    ActiveRecord::Base.uncached do
      found_parrot.name = "Mary"
      found_parrot.save
    end

    # Now reload, and verify that it gets the DB version, and not the querycache version
    found_parrot.reload
    assert_equal "Mary", found_parrot.name

    found_parrot = Parrot.find(parrot.id)
    assert_equal "Mary", found_parrot.name
  ensure
    ActiveRecord::Base.connection.disable_query_cache!
  end

  class SaveTest < ActiveRecord::TestCase
    self.use_transactional_tests = false

    def test_save_touch_false
      widget = Class.new(ActiveRecord::Base) do
        connection.create_table :widgets, force: true do |t|
          t.string :name
          t.timestamps null: false
        end

        self.table_name = :widgets
      end

      instance = widget.create!(
        name: "Bob",
        created_at: 1.day.ago,
        updated_at: 1.day.ago)

      created_at = instance.created_at
      updated_at = instance.updated_at

      instance.name = "Barb"
      instance.save!(touch: false)
      assert_equal instance.created_at, created_at
      assert_equal instance.updated_at, updated_at
    ensure
      ActiveRecord::Base.connection.drop_table widget.table_name
      widget.reset_column_information
    end
  end

  def test_reset_column_information_resets_children
    child = Class.new(Topic)
    child.new # force schema to load

    ActiveRecord::Base.connection.add_column(:topics, :foo, :string)
    Topic.reset_column_information

    assert_equal "bar", child.new(foo: :bar).foo
  ensure
    ActiveRecord::Base.connection.remove_column(:topics, :foo)
    Topic.reset_column_information
  end
end
