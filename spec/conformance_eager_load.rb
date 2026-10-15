# frozen_string_literal: true

# conformance-kit's audit.require (.conformance.yml): boots a minimal Rails app,
# then loads every DocsKit and DocsUI constant, so `conformance-audit --strict`
# (strict_autoloads) audits the whole gem rather than what a spec happened to
# touch. The app is needed because DocsUI::Page includes
# Phlex::Rails::Helpers::Routes, which reads Rails.application at load. Booting
# it runs the engine's after_initialize, so the audit sees the configuration
# as DocsKit.finalize! leaves it.
require "rails"
require "action_controller/railtie"
require "phlex/rails"
require "daisy_ui"
require "docs_kit"

gem_root = File.expand_path("..", __dir__)

module DocsKitConformance
  class Application < Rails::Application
    config.root = File.expand_path("../tmp/conformance_app", __dir__) # gitignored; nothing is written there
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "docs-kit-conformance"
  end
end
DocsKitConformance::Application.initialize!

# The gem's own zeitwerk loader: lib/docs_kit/** and app/components/docs_ui/**.
ObjectSpace.each_object(Zeitwerk::Loader).find { |loader| loader.tag == "docs_kit" }.eager_load

# Outside that loader: the engine's controllers (Rails autoloads them in a
# host), the generators (Rails' generator system loads them) and the
# docs_kit:og task's screenshot generator (an explicit require from the task).
Dir[File.join(gem_root, "app/controllers/docs_kit/*.rb")].each { |file| require file }
require "rails/generators"
Dir[File.join(gem_root, "lib/generators/**/*.rb")].each { |file| require file }
require "docs_kit/og_generator"
