# frozen_string_literal: true

module DocsKit
  # The built-in read-only MCP endpoint — one gem controller, host-drawn route
  # (same shape as DocsKit::LlmsController/SearchController; the engine adds no
  # routes):
  #
  #   # config/routes.rb
  #   post  "/mcp" => "docs_kit/mcp#create"
  #   match "/mcp" => "docs_kit/mcp#method_not_allowed", via: %i[get delete]
  #
  # A user adds `https://docs.example.com/mcp` to Claude Code / Claude.ai / Cursor
  # once and the docs become first-class agent tools (list_pages / get_page /
  # search_docs) over the SAME registry the site renders from. See
  # DocsKit::McpServer / DocsKit::McpTools.
  #
  # Stateless JSON-RPC: each POST is independent (no SSE session), so it works
  # behind the existing Kamal/Cloudflare deploy unchanged. #create delegates the
  # whole protocol to DocsKit::McpServer#handle_json — the SDK parses the request,
  # dispatches the tool, and serializes the response (including JSON-RPC errors),
  # so the controller never hand-rolls the protocol.
  #
  # OFF unless BOTH the optional `mcp` gem is present AND the site left c.mcp on
  # (DocsKit.configuration#mcp_enabled?). A site without the gem, or with
  # c.mcp = false, gets a 404 here and is byte-identical to before this feature.
  class McpController < ActionController::Base
    # A JSON-RPC POST carries no CSRF token to verify (there's no form, no
    # session — an agent posts a raw JSON body). Unlike the GET-only text
    # endpoints (which use :null_session so csrf_meta_tags resolves in a rendered
    # <head>), this action renders JSON only and never a Shell, so drop forgery
    # protection outright.
    skip_forgery_protection

    # MCP tool calls run in the request's version scope; the version-aware tool
    # arguments (issue #61 phase 6) layer per-call resolution on top of this.
    include DocsKit::Scoping

    def create
      return head(:not_found) unless docs_config.mcp_enabled?

      server = DocsKit::McpServer.build(docs_config, base_url: request.base_url, view_context:)
      return head(:not_found) unless server

      # #handle_json returns an already-serialized JSON string, so render it as the
      # raw body with the JSON content type — `render json:` would re-encode the
      # string (wrapping it in quotes), corrupting the JSON-RPC envelope.
      render body: server.handle_json(request.body.read), content_type: "application/json"
    end

    # Read-only + stateless: the endpoint speaks JSON-RPC over POST only. There is
    # no standalone SSE stream (GET) and no session to terminate (DELETE), so both
    # are 405 rather than the SDK's session machinery.
    def method_not_allowed
      head :method_not_allowed
    end

    private

    # NOT named #config — ActionController::Base#config is the Rails config object
    # and RequestForgeryProtection delegates to it; shadowing it breaks forgery
    # handling (see LlmsController). The DocsKit config reader is #docs_config.
    def docs_config = DocsKit.configuration
  end
end
