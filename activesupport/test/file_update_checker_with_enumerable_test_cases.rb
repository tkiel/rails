require 'fileutils'

module FileUpdateCheckerWithEnumerableTestCases
  include FileUtils

  def wait
    # noop
  end

  def touch(files)
    sleep 1
    super
  end

  def setup
    @tmpdir = Dir.mktmpdir(nil, __dir__)

    @files = %w(foo.rb bar.rb baz.rb).map {|f| "#{@tmpdir}/#{f}"}
    FileUtils.touch(@files)
  end

  def teardown
    rm_rf(@tmpdir)
  end

  def test_should_not_execute_the_block_if_no_paths_are_given
    i = 0

    checker = new_checker { i += 1 }

    assert !checker.execute_if_updated
    assert_equal 0, i
  end

  def test_should_not_invoke_the_block_if_no_file_has_changed
    i = 0

    checker = new_checker(@files) { i += 1 }

    assert !checker.execute_if_updated
    assert_equal 0, i
  end

  def test_should_invoke_the_block_if_a_file_has_changed
    i = 0

    checker = new_checker(@files) { i += 1 }

    touch(@files)
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_updated_should_become_true_when_watched_files_are_deleted
    i = 0

    checker = new_checker(@files) { i += 1 }
    assert !checker.updated?

    rm_f(@files)
    wait

    assert checker.updated?
  end

  def test_should_be_robust_enough_to_handle_deleted_files
    i = 0

    checker = new_checker(@files) { i += 1 }

    rm_f(@files)
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_should_be_robust_to_handle_files_with_wrong_modified_time
    i = 0

    now = Time.now
    time = Time.mktime(now.year + 1, now.month, now.day) # wrong mtime from the future
    File.utime(time, time, @files[0])

    checker = new_checker(@files) { i += 1 }

    touch(@files[1..-1])
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_should_cache_updated_result_until_execute
    i = 0

    checker = new_checker(@files) { i += 1 }
    assert !checker.updated?

    touch(@files)
    wait

    assert checker.updated?
    checker.execute
    assert !checker.updated?
  end

  def test_should_invoke_the_block_if_a_watched_dir_changes
    i = 0

    checker = new_checker([], @tmpdir => :rb) { i += 1 }

    touch(@files)
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_should_not_invoke_the_block_if_a_watched_dir_does_not_change
    i = 0

    checker = new_checker([], @tmpdir => :txt) { i += 1 }

    touch(@files)
    wait

    assert !checker.execute_if_updated
    assert_equal 0, i
  end

  def test_does_not_assume_files_exist_on_instantiation
    i = 0

    non_existing = "#{@tmpdir}/non_existing.rb"
    checker = new_checker([non_existing]) { i += 1 }

    touch(non_existing)
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_detects_files_in_new_subdirectories
    i = 0

    checker = new_checker([], @tmpdir => :rb) { i += 1 }

    subdir = "#{@tmpdir}/subdir"
    mkdir(subdir)
    wait

    assert !checker.execute_if_updated
    assert_equal 0, i

    touch("#{subdir}/nested.rb")
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_looked_up_extensions_are_inherited_in_subdirectories_not_listening_to_them
    i = 0

    subdir = "#{@tmpdir}/subdir"
    mkdir(subdir)

    checker = new_checker([], @tmpdir => :rb, subdir => :txt) { i += 1 }

    touch("#{@tmpdir}/new.txt")
    wait

    assert !checker.execute_if_updated
    assert_equal 0, i

    # subdir does not look for Ruby files, but its parent @tmpdir does.
    touch("#{subdir}/nested.rb")
    wait

    assert checker.execute_if_updated
    assert_equal 1, i

    touch("#{subdir}/nested.txt")
    wait

    assert checker.execute_if_updated
    assert_equal 2, i
  end
end
