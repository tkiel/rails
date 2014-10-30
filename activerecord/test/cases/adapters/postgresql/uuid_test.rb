# encoding: utf-8

require "cases/helper"
require 'active_record/base'
require 'active_record/connection_adapters/postgresql_adapter'

module PostgresqlUUIDHelper
  def connection
    @connection ||= ActiveRecord::Base.connection
  end

  def drop_table(name)
    connection.execute "drop table if exists #{name}"
  end
end

class PostgresqlUUIDTest < ActiveRecord::TestCase
  include PostgresqlUUIDHelper

  class UUIDType < ActiveRecord::Base
    self.table_name = "uuid_data_type"
  end

  setup do
    connection.create_table "uuid_data_type" do |t|
      t.uuid 'guid'
    end
  end

  teardown do
    drop_table "uuid_data_type"
  end

  def test_change_column_default
    @connection.add_column :uuid_data_type, :thingy, :uuid, null: false, default: "uuid_generate_v1()"
    UUIDType.reset_column_information
    column = UUIDType.columns_hash['thingy']
    assert_equal "uuid_generate_v1()", column.default_function

    @connection.change_column :uuid_data_type, :thingy, :uuid, null: false, default: "uuid_generate_v4()"

    UUIDType.reset_column_information
    column = UUIDType.columns_hash['thingy']
    assert_equal "uuid_generate_v4()", column.default_function
  ensure
    UUIDType.reset_column_information
  end

  def test_data_type_of_uuid_types
    column = UUIDType.columns_hash["guid"]
    assert_equal :uuid, column.type
    assert_equal "uuid", column.sql_type
    assert_not column.number?
    assert_not column.binary?
    assert_not column.array
  end

  def test_treat_blank_uuid_as_nil
    UUIDType.create! guid: ''
    assert_equal(nil, UUIDType.last.guid)
  end

  def test_treat_invalid_uuid_as_nil
    uuid = UUIDType.create! guid: 'foobar'
    assert_equal(nil, uuid.guid)
  end

  def test_invalid_uuid_dont_modify_before_type_cast
    uuid = UUIDType.new guid: 'foobar'
    assert_equal 'foobar', uuid.guid_before_type_cast
  end

  def test_rfc_4122_regex
    # Valid uuids
    ['A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11',
     '{a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11}',
     'a0eebc999c0b4ef8bb6d6bb9bd380a11',
     'a0ee-bc99-9c0b-4ef8-bb6d-6bb9-bd38-0a11',
     '{a0eebc99-9c0b4ef8-bb6d6bb9-bd380a11}'].each do |valid_uuid|
      uuid = UUIDType.new guid: valid_uuid
      assert_not_nil uuid.guid
    end

    # Invalid uuids
    [['A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11'],
     Hash.new,
     0,
     0.0,
     true,
     'Z0000C99-9C0B-4EF8-BB6D-6BB9BD380A11',
     '{a0eebc99-9c0b-4ef8-fb6d-6bb9bd380a11}',
     'a0eebc999r0b4ef8ab6d6bb9bd380a11',
     'a0ee-bc99------4ef8-bb6d-6bb9-bd38-0a11',
     '{a0eebc99-bb6d6bb9-bd380a11}'].each do |invalid_uuid|
      uuid = UUIDType.new guid: invalid_uuid
      assert_nil uuid.guid
    end
  end

  def test_uuid_formats
    ["A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11",
     "{a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11}",
     "a0eebc999c0b4ef8bb6d6bb9bd380a11",
     "a0ee-bc99-9c0b-4ef8-bb6d-6bb9-bd38-0a11",
     "{a0eebc99-9c0b4ef8-bb6d6bb9-bd380a11}"].each do |valid_uuid|
      UUIDType.create(guid: valid_uuid)
      uuid = UUIDType.last
      assert_equal "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11", uuid.guid
    end
  end
end

class PostgresqlLargeKeysTest < ActiveRecord::TestCase
  include PostgresqlUUIDHelper
  def setup
    connection.create_table('big_serials', id: :bigserial) do |t|
      t.string 'name'
    end
  end

  def test_omg
    schema = StringIO.new
    ActiveRecord::SchemaDumper.dump(connection, schema)
    assert_match "create_table \"big_serials\", id: :bigserial, force: true",
      schema.string
  end

  def teardown
    drop_table "big_serials"
  end
end

class PostgresqlUUIDGenerationTest < ActiveRecord::TestCase
  include PostgresqlUUIDHelper

  class UUID < ActiveRecord::Base
    self.table_name = 'pg_uuids'
  end

  setup do
    enable_extension!('uuid-ossp', connection)

    connection.create_table('pg_uuids', id: :uuid, default: 'uuid_generate_v1()') do |t|
      t.string 'name'
      t.uuid 'other_uuid', default: 'uuid_generate_v4()'
    end

    # Create custom PostgreSQL function to generate UUIDs
    # to test dumping tables which columns have defaults with custom functions
    connection.execute <<-SQL
    CREATE OR REPLACE FUNCTION my_uuid_generator() RETURNS uuid
    AS $$ SELECT * FROM uuid_generate_v4() $$
    LANGUAGE SQL VOLATILE;
    SQL

    # Create such a table with custom function as default value generator
    connection.create_table('pg_uuids_2', id: :uuid, default: 'my_uuid_generator()') do |t|
      t.string 'name'
      t.uuid 'other_uuid_2', default: 'my_uuid_generator()'
    end
  end

  teardown do
    drop_table "pg_uuids"
    drop_table 'pg_uuids_2'
    connection.execute 'DROP FUNCTION IF EXISTS my_uuid_generator();'
    disable_extension!('uuid-ossp', connection)
  end

  if ActiveRecord::Base.connection.supports_extensions?
    def test_id_is_uuid
      assert_equal :uuid, UUID.columns_hash['id'].type
      assert UUID.primary_key
    end

    def test_id_has_a_default
      u = UUID.create
      assert_not_nil u.id
    end

    def test_auto_create_uuid
      u = UUID.create
      u.reload
      assert_not_nil u.other_uuid
    end

    def test_pk_and_sequence_for_uuid_primary_key
      pk, seq = connection.pk_and_sequence_for('pg_uuids')
      assert_equal 'id', pk
      assert_equal nil, seq
    end

    def test_schema_dumper_for_uuid_primary_key
      schema = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, schema)
      assert_match(/\bcreate_table "pg_uuids", id: :uuid, default: "uuid_generate_v1\(\)"/, schema.string)
      assert_match(/t\.uuid   "other_uuid", default: "uuid_generate_v4\(\)"/, schema.string)
    end

    def test_schema_dumper_for_uuid_primary_key_with_custom_default
      schema = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, schema)
      assert_match(/\bcreate_table "pg_uuids_2", id: :uuid, default: "my_uuid_generator\(\)"/, schema.string)
      assert_match(/t\.uuid   "other_uuid_2", default: "my_uuid_generator\(\)"/, schema.string)
    end
  end
end

class PostgresqlUUIDTestNilDefault < ActiveRecord::TestCase
  include PostgresqlUUIDHelper

  setup do
    enable_extension!('uuid-ossp', connection)

    connection.create_table('pg_uuids', id: false) do |t|
      t.primary_key :id, :uuid, default: nil
      t.string 'name'
    end
  end

  teardown do
    drop_table "pg_uuids"
    disable_extension!('uuid-ossp', connection)
  end

  if ActiveRecord::Base.connection.supports_extensions?
    def test_id_allows_default_override_via_nil
      col_desc = connection.execute("SELECT pg_get_expr(d.adbin, d.adrelid) as default
                                    FROM pg_attribute a
                                    LEFT JOIN pg_attrdef d ON a.attrelid = d.adrelid AND a.attnum = d.adnum
                                    WHERE a.attname='id' AND a.attrelid = 'pg_uuids'::regclass").first
      assert_nil col_desc["default"]
    end
  end
end

class PostgresqlUUIDTestInverseOf < ActiveRecord::TestCase
  include PostgresqlUUIDHelper

  class UuidPost < ActiveRecord::Base
    self.table_name = 'pg_uuid_posts'
    has_many :uuid_comments, inverse_of: :uuid_post
  end

  class UuidComment < ActiveRecord::Base
    self.table_name = 'pg_uuid_comments'
    belongs_to :uuid_post
  end

  setup do
    enable_extension!('uuid-ossp', connection)

    connection.transaction do
      connection.create_table('pg_uuid_posts', id: :uuid) do |t|
        t.string 'title'
      end
      connection.create_table('pg_uuid_comments', id: :uuid) do |t|
        t.references :uuid_post, type: :uuid
        t.string 'content'
      end
    end
  end

  teardown do
      drop_table "pg_uuid_comments"
      drop_table "pg_uuid_posts"
      disable_extension!('uuid-ossp', connection)
  end

  if ActiveRecord::Base.connection.supports_extensions?
    def test_collection_association_with_uuid
      post    = UuidPost.create!
      comment = post.uuid_comments.create!
      assert post.uuid_comments.find(comment.id)
    end

    def test_find_with_uuid
      UuidPost.create!
      assert_raise ActiveRecord::RecordNotFound do
        UuidPost.find(123456)
      end

    end

    def test_find_by_with_uuid
      UuidPost.create!
      assert_nil UuidPost.find_by(id: 789)
    end
  end

end
