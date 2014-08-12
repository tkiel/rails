require 'active_job'
require 'rails'

module ActiveJob
  # = Active Job Railtie
  class Railtie < Rails::Railtie # :nodoc:
    initializer 'active_job' do
      ActiveSupport.on_load(:active_job) { self.logger = ::Rails.logger }
    end
  end
end
