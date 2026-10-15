# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The daisyui gem is published on rubygems. When the sibling checkout exists,
# track it so the kit develops against the same source the docs sites use;
# otherwise (CI, a fresh clone) fall back to the published gem via the gemspec's
# `daisyui >= 1.2` dependency.
gem "daisyui", path: "../daisyui" if File.directory?(File.expand_path("../daisyui", __dir__))

# The official MCP Ruby SDK. docs-kit's MCP server (DocsKit::McpServer /
# DocsKit::McpController) is an OPTIONAL, runtime-detected feature — the gem is
# NOT a runtime dependency (a consuming site adds it itself). It lives in its own
# group so the optional-dependency GATE can be exercised by excluding it:
# `bundle config set --local without mcp && bundle install` (a CI leg does exactly
# this). Without the gem the MCP specs self-skip and the feature must no-op.
group :mcp do
  gem "mcp"
end

group :development, :test do
  gem "async", require: false # runs conformance-kit's "fiber-safe under an Async reactor" example
  gem "conformance-kit", "~> 0.4", require: false # concurrency conformance gates (zoolutions/phlex-reactive#363)
  gem "rake"
  gem "rspec"
  gem "rubocop", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rake", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-thread_safety", ">= 0.8", require: false # conformance-kit's config/rubocop.yml (Tier 1 cops)
  gem "simplecov", require: false
end
