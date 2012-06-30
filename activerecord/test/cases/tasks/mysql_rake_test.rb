require 'cases/helper'
require 'mysql'

module ActiveRecord
  class MysqlDBCreateTest < ActiveRecord::TestCase
    def setup
      @connection    = stub(:create_database => true)
      @configuration = {
        'adapter'  => 'mysql',
        'database' => 'my-app-db'
      }

      ActiveRecord::Base.stubs(:connection).returns(@connection)
      ActiveRecord::Base.stubs(:establish_connection).returns(true)
    end

    def test_establishes_connection_without_database
      ActiveRecord::Base.expects(:establish_connection).
        with('adapter' => 'mysql', 'database' => nil)

      ActiveRecord::Tasks::DatabaseTasks.create @configuration
    end

    def test_creates_database_with_default_options
      @connection.expects(:create_database).
        with('my-app-db', {:charset => 'utf8', :collation => 'utf8_unicode_ci'})

      ActiveRecord::Tasks::DatabaseTasks.create @configuration
    end

    def test_creates_database_with_given_options
      @connection.expects(:create_database).
        with('my-app-db', {:charset => 'latin', :collation => 'latin_ci'})

      ActiveRecord::Tasks::DatabaseTasks.create @configuration.merge(
        'charset' => 'latin', 'collation' => 'latin_ci'
      )
    end

    def test_establishes_connection_to_database
      ActiveRecord::Base.expects(:establish_connection).with(@configuration)

      ActiveRecord::Tasks::DatabaseTasks.create @configuration
    end
  end

  class MysqlDBCreateAsRootTest < ActiveRecord::TestCase
    def setup
      @connection    = stub(:create_database => true, :execute => true)
      @error         = Mysql::Error.new "Invalid permissions"
      @configuration = {
        'adapter'  => 'mysql',
        'database' => 'my-app-db',
        'username' => 'pat',
        'password' => 'wossname'
      }

      $stdin.stubs(:gets).returns("secret\n")
      $stdout.stubs(:print).returns(nil)
      @error.stubs(:errno).returns(1045)
      ActiveRecord::Base.stubs(:connection).returns(@connection)
      ActiveRecord::Base.stubs(:establish_connection).raises(@error).then.
        returns(true)
    end

    def test_root_password_is_requested
      $stdin.expects(:gets).returns("secret\n")

      ActiveRecord::Tasks::DatabaseTasks.create @configuration
    end

    def test_connection_established_as_root
      ActiveRecord::Base.expects(:establish_connection).with({
        'adapter'  => 'mysql',
        'database' => nil,
        'username' => 'root',
        'password' => 'secret'
      })

      ActiveRecord::Tasks::DatabaseTasks.create @configuration
    end

    def test_database_created_by_root
      @connection.expects(:create_database).
        with('my-app-db', :charset => 'utf8', :collation => 'utf8_unicode_ci')

      ActiveRecord::Tasks::DatabaseTasks.create @configuration
    end

    def test_grant_privileges_for_normal_user
      @connection.expects(:execute).with("GRANT ALL PRIVILEGES ON my-app-db.* TO 'pat'@'localhost' IDENTIFIED BY 'wossname' WITH GRANT OPTION;")

      ActiveRecord::Tasks::DatabaseTasks.create @configuration
    end

    def test_connection_established_as_normal_user
      ActiveRecord::Base.expects(:establish_connection).returns do
        ActiveRecord::Base.expects(:establish_connection).with({
          'adapter'  => 'mysql',
          'database' => 'my-app-db',
          'username' => 'pat',
          'password' => 'secret'
        })

        raise @error
      end

      ActiveRecord::Tasks::DatabaseTasks.create @configuration
    end

    def test_sends_output_to_stderr_when_other_errors
      @error.stubs(:errno).returns(42)

      $stderr.expects(:puts).at_least_once.returns(nil)

      ActiveRecord::Tasks::DatabaseTasks.create @configuration
    end
  end

  class MySQLDBDropTest < ActiveRecord::TestCase
    def setup
      @connection    = stub(:drop_database => true)
      @configuration = {
        'adapter'  => 'mysql',
        'database' => 'my-app-db'
      }

      ActiveRecord::Base.stubs(:connection).returns(@connection)
      ActiveRecord::Base.stubs(:establish_connection).returns(true)
    end

    def test_establishes_connection_to_mysql_database
      ActiveRecord::Base.expects(:establish_connection).with @configuration

      ActiveRecord::Tasks::DatabaseTasks.drop @configuration
    end

    def test_drops_database
      @connection.expects(:drop_database).with('my-app-db')

      ActiveRecord::Tasks::DatabaseTasks.drop @configuration
    end
  end

  class MySQLPurgeTest < ActiveRecord::TestCase
    def setup
      @connection    = stub(:recreate_database => true)
      @configuration = {
        'adapter'  => 'mysql',
        'database' => 'test-db'
      }

      ActiveRecord::Base.stubs(:connection).returns(@connection)
      ActiveRecord::Base.stubs(:establish_connection).returns(true)
    end

    def test_establishes_connection_to_test_database
      ActiveRecord::Base.expects(:establish_connection).with(:test)

      ActiveRecord::Tasks::DatabaseTasks.purge @configuration
    end

    def test_recreates_database_with_the_default_options
      @connection.expects(:recreate_database).
        with('test-db', {:charset => 'utf8', :collation => 'utf8_unicode_ci'})

      ActiveRecord::Tasks::DatabaseTasks.purge @configuration
    end

    def test_recreates_database_with_the_given_options
      @connection.expects(:recreate_database).
        with('test-db', {:charset => 'latin', :collation => 'latin_ci'})

      ActiveRecord::Tasks::DatabaseTasks.purge @configuration.merge(
        'charset' => 'latin', 'collation' => 'latin_ci'
      )
    end
  end

  class MysqlDBCharsetTest < ActiveRecord::TestCase
    def setup
      @connection    = stub(:create_database => true)
      @configuration = {
        'adapter'  => 'mysql',
        'database' => 'my-app-db'
      }

      ActiveRecord::Base.stubs(:connection).returns(@connection)
      ActiveRecord::Base.stubs(:establish_connection).returns(true)
    end

    def test_db_retrieves_charset
      @connection.expects(:charset)
      ActiveRecord::Tasks::DatabaseTasks.charset @configuration
    end
  end

  class MysqlDBCollationTest < ActiveRecord::TestCase
    def setup
      @connection    = stub(:create_database => true)
      @configuration = {
        'adapter'  => 'mysql',
        'database' => 'my-app-db'
      }

      ActiveRecord::Base.stubs(:connection).returns(@connection)
      ActiveRecord::Base.stubs(:establish_connection).returns(true)
    end

    def test_db_retrieves_collation
      @connection.expects(:collation)
      ActiveRecord::Tasks::DatabaseTasks.collation @configuration
    end
  end

  class MySQLStructureDumpTest < ActiveRecord::TestCase
    def setup
      @connection    = stub(:structure_dump => true)
      @configuration = {
        'adapter'  => 'mysql',
        'database' => 'test-db'
      }

      ActiveRecord::Base.stubs(:connection).returns(@connection)
      ActiveRecord::Base.stubs(:establish_connection).returns(true)
    end

    def test_structure_dump
      filename = "awesome-file.sql"
      ActiveRecord::Base.expects(:establish_connection).with(@configuration)
      @connection.expects(:structure_dump)

      ActiveRecord::Tasks::DatabaseTasks.structure_dump(@configuration, filename)
      assert File.exists?(filename)
    ensure
      FileUtils.rm(filename)
    end
  end

  class MySQLStructureLoadTest < ActiveRecord::TestCase
    def setup
      @connection    = stub
      @configuration = {
        'adapter'  => 'mysql',
        'database' => 'test-db'
      }

      ActiveRecord::Base.stubs(:connection).returns(@connection)
      ActiveRecord::Base.stubs(:establish_connection).returns(true)
    end

    def test_structure_load
      filename = "awesome-file.sql"
      ActiveRecord::Base.expects(:establish_connection).with(@configuration)
      @connection.expects(:execute).twice

      open(filename, 'w') { |f| f.puts("SELECT CURDATE();") }
      ActiveRecord::Tasks::DatabaseTasks.structure_load(@configuration, filename)
    ensure
      FileUtils.rm(filename)
    end
  end

end
