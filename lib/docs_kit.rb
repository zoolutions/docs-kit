# frozen_string_literal: true

require "phlex"
require "rouge"
require "zeitwerk"

require_relative "docs_kit/version"
require_relative "docs_kit/shareable"
require_relative "docs_kit/configuration"

# DocsKit — a reusable docs-site component library: the shared Phlex chrome
# (shell, sidebar, code block, theme switcher, page kit) that lets several docs
# sites look identical while differing only in configuration.
#
# Components live under the `Docs::` namespace and are exposed as a Phlex::Kit,
# so a host base view can `include Docs` and call `Shell(...)`, `Page(...)`,
# `Code(...)`, etc., or always use the namespaced `render Docs::Shell.new(...)`.
module DocsKit
  class Error < StandardError; end

  # Built at load, never lazily: no first-request race to build two.
  @configuration = Configuration.new

  class << self
    # The current configuration. Reset with DocsKit.reset_configuration!.
    # Assigned at load and by reset_configuration! (boot, specs) on the main
    # Ractor; request threads only read it. Main-only (.conformance.yml): it
    # holds the host's per-request callables (brand, nav, version_badge, ...).
    attr_reader :configuration

    # Re-opens a finalized configuration first (a development reload re-runs
    # the host's to_prepare configure), so every setting takes effect.
    def configure
      configuration.reopen!
      yield(configuration)
      configuration.validate!
    end

    # Resolves the configuration's per-render lookups once (see
    # Configuration#finalize!). The engine calls it after the host has
    # configured the kit, unless code reloading is on.
    def finalize!
      configuration.finalize!
    end

    # A fresh default configuration (specs; a host that re-boots its config).
    # Runs at boot or between examples, never on a request.
    def reset_configuration!
      @configuration = Configuration.new # rubocop:disable ThreadSafety/ClassInstanceVariable
    end
  end
end

# The DocsUI namespace is a Phlex::Kit so `include DocsUI` exposes every
# component constant as a bare callable method (DocsUI::Shell(), DocsUI::Code(),
# ...). Named DocsUI (not Docs) so it never collides with a host app's own
# `Views::Docs` page namespace, and to match the UI/AdminUI/DocsUI kit convention.
# Defined before loader.setup so zeitwerk autoloads its children into this
# already-extended module.
module DocsUI
  extend Phlex::Kit
end

loader = Zeitwerk::Loader.new
loader.tag = "docs_kit"
loader.inflector.inflect("docs_kit" => "DocsKit", "docs_ui" => "DocsUI")
# DocsKit::* support code (registry mixin, engine helpers) under lib/docs_kit/,
# excluding the eagerly-required files below.
loader.push_dir(File.expand_path("docs_kit", __dir__), namespace: DocsKit)
# The shippable Phlex components under app/components/docs_ui/ → DocsUI::*.
loader.push_dir(File.expand_path("../app/components/docs_ui", __dir__), namespace: DocsUI)
loader.ignore(File.expand_path("docs_kit/version.rb", __dir__))
loader.ignore(File.expand_path("docs_kit/configuration.rb", __dir__))
# Required eagerly above (configuration.rb's constants use it at load).
loader.ignore(File.expand_path("docs_kit/shareable.rb", __dir__))
# Required eagerly by configuration.rb (a plain-Ruby value object, no Rails), so
# ignore it here too or zeitwerk double-manages the constant.
loader.ignore(File.expand_path("docs_kit/seo_config.rb", __dir__))
loader.ignore(File.expand_path("docs_kit/landing_config.rb", __dir__))
# Required eagerly by landing_config.rb (the LandingConfig::Logo alias resolves
# it at require time, before this loader is set up), so ignore it here too.
loader.ignore(File.expand_path("docs_kit/brand_logo.rb", __dir__))
# Loaded ONLY by the host's docs_kit:og rake task (an explicit require), never at
# gem runtime — so its Rack/browser tooling is never pulled into a host that
# doesn't run the task. Ignore it so eager_load! doesn't require it.
loader.ignore(File.expand_path("docs_kit/og_generator.rb", __dir__))
# docs_kit/rubocop.rb is the RuboCop-cop entry point: it defines cops under
# RuboCop::Cop::DocsKit::*, not a DocsKit::Rubocop constant, so zeitwerk must not
# manage it. It (and the cops under lib/rubocop/, which are outside the loader's
# push_dirs entirely) load only when a `.rubocop.yml` requires "docs_kit/rubocop".
loader.ignore(File.expand_path("docs_kit/rubocop.rb", __dir__))
# engine.rb is required explicitly below only under Rails, so zeitwerk never
# manages it (it would otherwise expect a DocsKit::Engine constant outside Rails).
loader.ignore(File.expand_path("docs_kit/engine.rb", __dir__))
# The Rails application template (docs_kit/templates) is executed inside
# `rails new`, not autoloadable Ruby — ignore it so eager_load! doesn't try to
# load it (it references template-DSL locals like `app_name`). Generators are
# loaded by Rails' generator system, not this loader.
loader.ignore(File.expand_path("docs_kit/templates", __dir__))
loader.setup

require_relative "docs_kit/engine" if defined?(Rails::Engine)
