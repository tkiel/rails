module ActionPack
  # Returns the version of the currently loaded ActionPack as a Gem::Version
  def self.version
    Gem::Version.new "4.2.0.alpha"
  end

  module VERSION #:nodoc:
    MAJOR, MINOR, TINY, PRE = ActionPack.version.segments
    STRING = ActionPack.version.to_s
  end
end
