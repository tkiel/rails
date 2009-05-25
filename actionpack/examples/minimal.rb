# Pass NEW=1 to run with the new Base
ENV['RAILS_ENV'] ||= 'production'
ENV['NO_RELOAD'] ||= '1'

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require 'action_controller'
require 'action_controller/new_base' if ENV['NEW']
require 'benchmark'

class Runner
  def initialize(app)
    @app = app
  end

  def call(env)
    env['n'].to_i.times { @app.call(env) }
    @app.call(env).tap { |response| report(env, response) }
  end

  def report(env, response)
    out = env['rack.errors']
    out.puts response[0], response[1].to_yaml, '---'
    response[2].each { |part| out.puts part }
    out.puts '---'
  end

  def self.run(app, n)
    env = { 'n' => n, 'rack.input' => StringIO.new(''), 'rack.errors' => $stdout }
    t = Benchmark.realtime { new(app).call(env) }
    puts "%d ms / %d req = %d usec/req" % [10**3 * t, n, 10**6 * t / n]
  end
end


N = (ENV['N'] || 1000).to_i

class BasePostController < ActionController::Base
  def index
    render :text => ''
  end

  Runner.run(action(:index), N)
end

if ActionController.const_defined?(:Http)
  class HttpPostController < ActionController::Http
    def index
      self.response_body = ''
    end

    Runner.run(action(:index), N)
  end
end
