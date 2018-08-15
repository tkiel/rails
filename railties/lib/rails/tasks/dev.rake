# frozen_string_literal: true

require "rails/command"
require "active_support/deprecation"

namespace :dev do
  desc "Toggle development mode caching on/off"
  task :cache do
    ActiveSupport::Deprecation.warn("Using `bin/rake dev:cache` is deprecated and will be removed in Rails 6.1. Use `bin/rails dev:cache` instead.\n")
    Rails::Command.invoke "dev:cache"
  end
end
