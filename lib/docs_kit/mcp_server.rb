# frozen_string_literal: true

require "json"

module DocsKit
  # Builds the read-only MCP::Server a docs-kit site exposes at POST /mcp — a
  # stateless JSON-RPC skin over DocsKit::McpTools, so an agent (Claude Code,
  # Claude.ai, Cursor) adds one URL and the docs become first-class tools:
  #
  #   server = DocsKit::McpServer.build(DocsKit.configuration, base_url:, view_context:)
  #   server.handle_json(request.body.read)   # → the JSON-RPC response string
  #
  # The `mcp` gem is OPTIONAL and runtime-detected (docs-kit depends on it in no
  # gemspec list). .build returns nil when the gem is absent, and the controller
  # only reaches here when DocsKit.configuration#mcp_enabled? — so a site without
  # the gem, or with c.mcp = false, is byte-identical to before this feature.
  #
  # base_url + view_context ride in the server_context (the SDK threads it to
  # every tool block), so the tools render each page's Markdown twin through the
  # Rails view context and absolutize URLs — the same seam LlmsController#full
  # uses. The three tools mirror DocsKit::McpTools one-to-one.
  module McpServer
    module_function

    # The MCP::Server for this config, or nil when the `mcp` gem isn't loadable.
    # base_url/view_context flow to the tools via server_context.
    def build(config, base_url: nil, view_context: nil)
      return unless mcp_available?

      server = MCP::Server.new(
        name: config.brand_text,
        version: DocsKit::VERSION,
        instructions: instructions_for(config, base_url),
        server_context: { config:, base_url:, view_context: }
      )
      define_tools(server)
      server
    end

    # Whether the official MCP SDK is loadable — the runtime-detection gate. Kept
    # as a seam so specs can force the gem-absent branch without unloading it.
    def mcp_available?
      require "mcp"
      defined?(::MCP::Server) ? true : false
    rescue LoadError
      false
    end

    # Server instructions: the site's tagline (when set) plus a pointer to
    # /llms.txt, so an agent knows what these docs cover and where the full index
    # lives. base_url absolutizes the /llms.txt hint when available.
    def instructions_for(config, base_url)
      llms = base_url ? "#{base_url.chomp('/')}/llms.txt" : "/llms.txt"
      lines = []
      tagline = config.tagline
      lines << tagline.to_s if tagline && !tagline.to_s.empty?
      lines << "Read-only documentation tools for #{config.brand_text}. " \
               "Use search_docs to find sections, get_page to read a page's Markdown, " \
               "and list_pages to enumerate the docs. Full index: #{llms}."
      lines.join(" ")
    end

    # Register the three read-only tools. Each block pulls config + render context
    # from server_context, calls the matching DocsKit::McpTools function, and
    # returns the result as pretty JSON text (agents consume structured data).
    def define_tools(server)
      define_list_pages(server)
      define_get_page(server)
      define_search_docs(server)
    end

    def define_list_pages(server)
      server.define_tool(
        name: "list_pages",
        description: "List every documentation page: its slug, title, group, and URL. " \
                     "Use the slug with get_page.",
        input_schema: { type: "object", properties: {}, required: [] }
      ) do |server_context:|
        cfg = server_context[:config]
        McpServer.json_response(McpTools.list_pages(cfg, base_url: server_context[:base_url]))
      end
    end

    def define_get_page(server)
      server.define_tool(
        name: "get_page",
        description: "Fetch one documentation page as Markdown, by its slug (see list_pages). " \
                     "Returns the page's full Markdown twin.",
        input_schema: {
          type: "object",
          properties: { slug: { type: "string", description: "The page slug, e.g. \"installation\"." } },
          required: ["slug"]
        }
      ) do |slug:, server_context:|
        cfg = server_context[:config]
        McpServer.json_response(
          McpTools.get_page(cfg, slug:, base_url: server_context[:base_url],
                                 view_context: server_context[:view_context])
        )
      end
    end

    def define_search_docs(server)
      server.define_tool(
        name: "search_docs",
        description: "Full-text search across all documentation pages. " \
                     "Returns ranked hits with the page, section, URL, and a snippet.",
        input_schema: {
          type: "object",
          properties: { query: { type: "string", description: "The search terms." } },
          required: ["query"]
        }
      ) do |query:, server_context:|
        cfg = server_context[:config]
        McpServer.json_response(
          McpTools.search_docs(cfg, query:, base_url: server_context[:base_url],
                                    view_context: server_context[:view_context])
        )
      end
    end

    # Wrap a Ruby data payload as a single-text MCP tool response, the data as
    # pretty JSON so an agent parses structured fields (not prose).
    def json_response(payload)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(payload) }])
    end
  end
end
