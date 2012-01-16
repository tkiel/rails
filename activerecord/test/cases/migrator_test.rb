require "cases/helper"
require "cases/migration/helper"

module ActiveRecord
  class MigratorTest < ActiveRecord::TestCase
    self.use_transactional_fixtures = false

    # Use this class to sense if migrations have gone
    # up or down.
    class Sensor < ActiveRecord::Migration
      attr_reader :went_up, :went_down

      def initialize name = self.class.name, version = nil
        super
        @went_up  = false
        @went_down = false
      end

      def up; @went_up = true; end
      def down; @went_down = true; end
    end

    def setup
      super
      ActiveRecord::SchemaMigration.create_table
      ActiveRecord::SchemaMigration.delete_all rescue nil
    end

    def teardown
      super
      ActiveRecord::SchemaMigration.delete_all rescue nil
    end

    def test_migrator_with_duplicate_names
      assert_raises(ActiveRecord::DuplicateMigrationNameError, "Multiple migrations have the name Chunky") do
        list = [Migration.new('Chunky'), Migration.new('Chunky')]
        ActiveRecord::Migrator.new(:up, list)
      end
    end

    def test_migrator_with_duplicate_versions
      assert_raises(ActiveRecord::DuplicateMigrationVersionError) do
        list = [Migration.new('Foo', 1), Migration.new('Bar', 1)]
        ActiveRecord::Migrator.new(:up, list)
      end
    end

    def test_migrator_with_missing_version_numbers
      assert_raises(ActiveRecord::UnknownMigrationVersionError) do
        list = [Migration.new('Foo', 1), Migration.new('Bar', 2)]
        ActiveRecord::Migrator.new(:up, list, 3).run
      end
    end

    def test_finds_migrations
      migrations = ActiveRecord::Migrator.migrations(MIGRATIONS_ROOT + "/valid")

      [[1, 'ValidPeopleHaveLastNames'], [2, 'WeNeedReminders'], [3, 'InnocentJointable']].each_with_index do |pair, i|
        assert_equal migrations[i].version, pair.first
        assert_equal migrations[i].name, pair.last
      end
    end

    def test_finds_migrations_in_subdirectories
      migrations = ActiveRecord::Migrator.migrations(MIGRATIONS_ROOT + "/valid_with_subdirectories")

      [[1, 'ValidPeopleHaveLastNames'], [2, 'WeNeedReminders'], [3, 'InnocentJointable']].each_with_index do |pair, i|
        assert_equal migrations[i].version, pair.first
        assert_equal migrations[i].name, pair.last
      end
    end

    def test_finds_migrations_from_two_directories
      directories = [MIGRATIONS_ROOT + '/valid_with_timestamps', MIGRATIONS_ROOT + '/to_copy_with_timestamps']
      migrations = ActiveRecord::Migrator.migrations directories

      [[20090101010101, "PeopleHaveHobbies"],
       [20090101010202, "PeopleHaveDescriptions"],
       [20100101010101, "ValidWithTimestampsPeopleHaveLastNames"],
       [20100201010101, "ValidWithTimestampsWeNeedReminders"],
       [20100301010101, "ValidWithTimestampsInnocentJointable"]].each_with_index do |pair, i|
        assert_equal pair.first, migrations[i].version
        assert_equal pair.last, migrations[i].name
       end
    end

    def test_deprecated_constructor
      assert_deprecated do
        ActiveRecord::Migrator.new(:up, MIGRATIONS_ROOT + "/valid")
      end
    end

    def test_relative_migrations
      list = Dir.chdir(MIGRATIONS_ROOT) do
        ActiveRecord::Migrator.migrations("valid/")
      end

      migration_proxy = list.find { |item|
        item.name == 'ValidPeopleHaveLastNames'
      }
      assert migration_proxy, 'should find pending migration'
    end

    def test_finds_pending_migrations
      ActiveRecord::SchemaMigration.create!(:version => '1')
      migration_list = [ Migration.new('foo', 1), Migration.new('bar', 3) ]
      migrations = ActiveRecord::Migrator.new(:up, migration_list).pending_migrations

      assert_equal 1, migrations.size
      assert_equal migration_list.last, migrations.first
    end

    def test_migrator_interleaved_migrations
      pass_one = [Sensor.new('One', 1)]

      ActiveRecord::Migrator.new(:up, pass_one).migrate
      assert pass_one.first.went_up
      refute pass_one.first.went_down

      pass_two = [Sensor.new('One', 1), Sensor.new('Three', 3)]
      ActiveRecord::Migrator.new(:up, pass_two).migrate
      refute pass_two[0].went_up
      assert pass_two[1].went_up
      assert pass_two.all? { |x| !x.went_down }

      pass_three = [Sensor.new('One', 1),
                    Sensor.new('Two', 2),
                    Sensor.new('Three', 3)]

      ActiveRecord::Migrator.new(:down, pass_three).migrate
      assert pass_three[0].went_down
      refute pass_three[1].went_down
      assert pass_three[2].went_down
    end

    def test_up_calls_up
      migrations = [Sensor.new(nil, 0), Sensor.new(nil, 1), Sensor.new(nil, 2)]
      ActiveRecord::Migrator.new(:up, migrations).migrate
      assert migrations.all? { |m| m.went_up }
      assert migrations.all? { |m| !m.went_down }
      assert_equal 2, ActiveRecord::Migrator.current_version
    end

    def test_down_calls_down
      test_up_calls_up

      migrations = [Sensor.new(nil, 0), Sensor.new(nil, 1), Sensor.new(nil, 2)]
      ActiveRecord::Migrator.new(:down, migrations).migrate
      assert migrations.all? { |m| !m.went_up }
      assert migrations.all? { |m| m.went_down }
      assert_equal 0, ActiveRecord::Migrator.current_version
    end

    def test_current_version
      ActiveRecord::SchemaMigration.create!(:version => '1000')
      assert_equal 1000, ActiveRecord::Migrator.current_version
    end

    def test_migrator_one_up
      calls, migrations = sensors(3)

      ActiveRecord::Migrator.new(:up, migrations, 1).migrate
      assert_equal [[:up, 0], [:up, 1]], calls
      calls.clear

      ActiveRecord::Migrator.new(:up, migrations, 2).migrate
      assert_equal [[:up, 2]], calls
    end

    def test_migrator_one_down
      calls, migrations = sensors(3)

      ActiveRecord::Migrator.new(:up, migrations).migrate
      assert_equal [[:up, 0], [:up, 1], [:up, 2]], calls
      calls.clear

      ActiveRecord::Migrator.new(:down, migrations, 1).migrate

      assert_equal [[:down, 2]], calls
    end

    def test_migrator_one_up_one_down
      calls, migrations = sensors(3)

      ActiveRecord::Migrator.new(:up, migrations, 1).migrate
      assert_equal [[:up, 0], [:up, 1]], calls
      calls.clear

      ActiveRecord::Migrator.new(:down, migrations, 0).migrate
      assert_equal [[:down, 1]], calls
    end

    def test_migrator_double_up
      calls, migrations = sensors(3)
      assert_equal(0, ActiveRecord::Migrator.current_version)

      ActiveRecord::Migrator.new(:up, migrations, 1).migrate
      assert_equal [[:up, 0], [:up, 1]], calls
      calls.clear

      ActiveRecord::Migrator.new(:up, migrations, 1).migrate
      assert_equal [], calls
    end

    def test_migrator_double_down
      calls, migrations = sensors(3)

      assert_equal(0, ActiveRecord::Migrator.current_version)

      ActiveRecord::Migrator.new(:up, migrations, 1).run
      assert_equal [[:up, 1]], calls
      calls.clear

      ActiveRecord::Migrator.new(:down, migrations, 1).run
      assert_equal [[:down, 1]], calls
      calls.clear

      ActiveRecord::Migrator.new(:down, migrations, 1).run
      assert_equal [], calls

      assert_equal(0, ActiveRecord::Migrator.current_version)
    end

    private
    def m(name, version, &block)
      x = Sensor.new name, version
      x.extend(Module.new {
        define_method(:up) { block.call(:up, x); super() }
        define_method(:down) { block.call(:down, x); super() }
      }) if block_given?
    end

    def sensors(count)
      calls = []
      migrations = 3.times.map { |i|
        m(nil, i) { |c,migration|
          calls << [c, migration.version]
        }
      }
      [calls, migrations]
    end
  end
end
