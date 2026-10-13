# frozen_string_literal: true

require "rails/engine"

module DocsKit
  # An asset/glue engine (no isolate_namespace, no routes/models). It makes the
  # gem's Phlex components autoloadable in the host app and exposes the controller
  # helper, so a docs site only adds the gem + its DocsKit.configure block.
  class Engine < ::Rails::Engine
    # The gem's OWN zeitwerk loader (in lib/docs_kit.rb) is the single owner of
    # the Docs::* components under app/components/docs. Rails would otherwise also
    # add an engine's app/* dirs to the host autoload paths and double-manage
    # those constants, so opt this engine's app/ out of Rails autoloading.
    config.autoload_paths = []
    config.eager_load_paths = []
    config.paths["app"].skip_eager_load!

    JAVASCRIPT_PATH = root.join("app/javascript")

    initializer "docs_kit.controller_helper" do
      ActiveSupport.on_load(:action_controller_base) do
        include DocsKit::Controller
      end
    end

    # Register the :md format (text/markdown) so a `.md` request routes and
    # `request.format.md?` is true — the trigger for the page's Markdown twin
    # (DocsKit::Controller#render_page). Guarded so re-registration (a host that
    # already declared :md) is a no-op rather than a duplicate-type error.
    initializer "docs_kit.mime_types" do
      Mime::Type.register("text/markdown", :md) unless Mime::Type.lookup_by_extension(:md)
    end

    # Serve the bundled Stimulus controller (docs_nav) as an asset.
    initializer "docs_kit.assets" do |app|
      app.config.assets.paths << JAVASCRIPT_PATH.to_s if app.config.respond_to?(:assets)
    end

    # Host-facing engine options. `config.docs_kit.auto_pin = false` (in
    # config/application.rb) keeps the gem's pin out of the host's shared import
    # map, for a host that pins `docs_kit/controllers` in a dedicated docs map.
    config.docs_kit = ActiveSupport::OrderedOptions.new
    config.docs_kit.auto_pin = true

    # Auto-pin the controller for importmap-rails consumers, so a host app gets
    # `docs_kit/controllers/docs_nav_controller` with no manual pin.
    initializer "docs_kit.importmap", before: "importmap" do |app|
      next unless app.config.respond_to?(:importmap)
      next unless app.config.docs_kit.auto_pin

      importmap = app.config.importmap
      importmap.paths << root.join("config/importmap.rb") if importmap.respond_to?(:paths)
      importmap.cache_sweepers << JAVASCRIPT_PATH if importmap.respond_to?(:cache_sweepers)
    end
  end
end
