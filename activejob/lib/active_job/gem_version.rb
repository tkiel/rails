# frozen_string_literal: true

module ActiveJob
  # Returns the version of the currently loaded Active Job as a <tt>Gem::Version</tt>
  def self.gem_version
    Gem::Version.new VERSION::STRING
  end

  module VERSION
    MAJOR = 6
    MINOR = 0
    TINY  = 0
    PRE   = "beta1"

    STRING = [MAJOR, MINOR, TINY, PRE].compact.join(".")
  end
end
