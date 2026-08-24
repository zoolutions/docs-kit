# frozen_string_literal: true

# Coverage. Start SimpleCov BEFORE requiring docs_kit so every lib/ file loaded
# below is tracked. CLAUDE.md sets the 80% floor; enforce it here so `rake` fails
# locally and in CI when coverage regresses. The generators/ tree is the install
# generator, exercised by spec/generators/**.
require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  skip "/spec/"
  group "Config", "lib/docs_kit/configuration.rb"
  group "Registry", "lib/docs_kit/registry.rb"
  group "Components", "app/components"
  group "Generators", "lib/generators"
  minimum_coverage 80
end

# Component specs render DocsUI:: Phlex components in isolation (no Rails
# request). Shell and Code compose phlex-rails value helpers (e.g.
# content_security_policy_nonce), so load phlex-rails here — plus the two
# ActiveSupport core-exts it and the theme-restore script rely on
# (String#html_safe / SafeBuffer, and #to_json). Rails provides all of these in
# a real app; the suite loads just enough to render the chrome standalone.
require "active_support/core_ext/string/output_safety"
require "active_support/json"
require "phlex/rails"

# DocsUI::Shell / Sidebar `include DaisyUI` (the daisyUI Phlex kit). The gem name
# is `daisyui`; the require path is `daisy_ui` — a consuming site loads it via
# `gem "daisyui", require: "daisy_ui"`. docs_kit itself never requires it (the
# host app does), so the standalone suite must load it here or the constant is
# undefined when a component is rendered.
require "daisy_ui"

require "docs_kit"

# The MCP server (DocsKit::McpServer) is an OPTIONAL, runtime-detected feature
# built on the `mcp` gem — docs-kit never depends on it at runtime. The suite
# loads it (dev/test group) so the MCP specs exercise the real SDK; MCP-integration
# examples guard on `defined?(MCP)`, so a `bundle install --without mcp` run
# (the optional-dependency gate) simply skips them and the rest stays green.
begin
  require "mcp"
rescue LoadError
  # mcp not bundled (the without-mcp gate leg) — the MCP specs self-skip.
end

# Shared spec helpers (spec/support/*). Explicit requires — the suite has no
# support-glob autoload, so add one line per helper file.
require_relative "support/open_api_helpers"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Each example starts from a clean configuration.
  config.before { DocsKit.reset_configuration! }
end
