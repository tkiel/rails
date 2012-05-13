class Hash
  # Return a new hash with all keys converted to strings.
  #
  #   { :name => 'Rob', :years => '28' }.stringify_keys
  #   #=> { "name" => "Rob", "years" => "28" }
  def stringify_keys
    result = {}
    keys.each do |key|
      result[key.to_s] = self[key]
    end
    result
  end

  # Destructively convert all keys to strings. Same as
  # +stringify_keys+, but modifies +self+.
  def stringify_keys!
    keys.each do |key|
      self[key.to_s] = delete(key)
    end
    self
  end

  # Return a new hash with all keys converted to symbols, as long as
  # they respond to +to_sym+.
  def symbolize_keys
    result = {}
    keys.each do |key|
      result[(key.to_sym rescue key)] = self[key]
    end
    result
  end
  alias_method :to_options,  :symbolize_keys

  # Destructively convert all keys to symbols, as long as they respond
  # to +to_sym+.
  def symbolize_keys!
    keys.each do |key|
      self[(key.to_sym rescue key)] = delete(key)
    end
    self
  end
  alias_method :to_options!, :symbolize_keys!

  # Validate all keys in a hash match *valid keys, raising ArgumentError on a mismatch.
  # Note that keys are NOT treated indifferently, meaning if you use strings for keys but assert symbols
  # as keys, this will fail.
  #
  # ==== Examples
  #   { :name => 'Rob', :years => '28' }.assert_valid_keys(:name, :age) # => raises "ArgumentError: Unknown key: years"
  #   { :name => 'Rob', :age => '28' }.assert_valid_keys('name', 'age') # => raises "ArgumentError: Unknown key: name"
  #   { :name => 'Rob', :age => '28' }.assert_valid_keys(:name, :age) # => passes, raises nothing
  def assert_valid_keys(*valid_keys)
    valid_keys.flatten!
    each_key do |k|
      raise ArgumentError.new("Unknown key: #{k}") unless valid_keys.include?(k)
    end
  end
end
