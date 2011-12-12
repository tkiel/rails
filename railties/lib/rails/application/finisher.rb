module Rails
  class Application
    module Finisher
      include Initializable
      $rails_rake_task = nil

      initializer :load_config_initializers do
        config.initializers_paths.each { |init| load(init) }
      end

      initializer :add_generator_templates do
        config.generators.templates.unshift(*paths["lib/templates"].existent)
      end

      initializer :ensure_autoload_once_paths_as_subset do
        extra = ActiveSupport::Dependencies.autoload_once_paths -
                ActiveSupport::Dependencies.autoload_paths

        unless extra.empty?
          abort <<-end_error
            autoload_once_paths must be a subset of the autoload_paths.
            Extra items in autoload_once_paths: #{extra * ','}
          end_error
        end
      end

      initializer :add_builtin_route do |app|
        if Rails.env.development?
          app.routes.append do
            match '/rails/info/properties' => "rails/info#properties"
          end
        end
      end

      initializer :build_middleware_stack do
        build_middleware_stack
      end

      initializer :define_main_app_helper do |app|
        app.routes.define_mounted_helper(:main_app)
      end

      initializer :add_to_prepare_blocks do
        config.to_prepare_blocks.each do |block|
          ActionDispatch::Reloader.to_prepare(&block)
        end
      end

      # This needs to happen before eager load so it happens
      # in exactly the same point regardless of config.cache_classes
      initializer :run_prepare_callbacks do
        ActionDispatch::Reloader.prepare!
      end

      initializer :eager_load! do
        if config.cache_classes && !$rails_rake_task
          ActiveSupport.run_load_hooks(:before_eager_load, self)
          eager_load!
        end
      end

      # All initialization is done, including eager loading in production
      initializer :finisher_hook do
        ActiveSupport.run_load_hooks(:after_initialize, self)
      end

      # Set app reload just after the finisher hook to ensure
      # routes added in the hook are still loaded.
      initializer :set_routes_reloader_hook do |app|
        app.set_routes_reloader_hook
      end

      # Set app reload just after the finisher hook to ensure
      # paths added in the hook are still loaded.
      initializer :set_dependencies_hook, :group => :all do |app|
        app.set_dependencies_hook
      end

      # Disable dependency loading during request cycle
      initializer :disable_dependency_loading do
        if config.cache_classes && !config.dependency_loading
          ActiveSupport::Dependencies.unhook!
        end
      end
    end
  end
end
