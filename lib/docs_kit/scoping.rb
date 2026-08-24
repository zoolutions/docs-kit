# frozen_string_literal: true

module DocsKit
  # Wraps a controller's actions in the request's DocsKit::Scope, so everything
  # rendered or enumerated during the action (Configuration#nav_groups,
  # LlmsText.pages, the search index) sees the same version the URL asked for.
  # Included by the gem's own controllers (Llms, Search, Mcp); a host's docs
  # controller gets the same behavior from DocsKit::Controller#render_page's own
  # wrapper instead — including this module there would around_action every host
  # action, which is not docs-kit's call to make.
  #
  # A plain module with an included hook, not an ActiveSupport::Concern — it has
  # no dependency chain and stays loadable in the Rails-free suite.
  module Scoping
    def self.included(base)
      base.around_action :docs_scope
    end

    private

    # The requested version (params[:version], falling back to the current
    # version — an unknown id degrades, never 500s) held in scope for the whole
    # action. nil on an unversioned site: today's behavior exactly.
    def docs_scope(&)
      DocsKit::Scope.with(version: DocsKit.configuration.resolve_version(params[:version]), &)
    end
  end
end
