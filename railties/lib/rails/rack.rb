module Rails
  module Rack
    autoload :Debugger,      "rails/rack/debugger"
    autoload :Logger,        "rails/rack/logger"
    autoload :LogTailer,     "rails/rack/log_tailer"
    autoload :TaggedLogging, "rails/rack/tagged_logging"
  end
end
