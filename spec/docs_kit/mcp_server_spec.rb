# frozen_string_literal: true

# DocsKit::McpServer wraps the pure DocsKit::McpTools functions into an
# MCP::Server (the official SDK) exposing list_pages / get_page / search_docs
# over stateless JSON-RPC. These specs drive the REAL SDK via #handle_json (no
# HTTP, no controller) — tools/list returns the three tools, and a tools/call
# round-trips through the registry. The whole thing is guarded on the optional
# `mcp` gem: without it the suite skips these (the optional-dependency gate) and
# .build must no-op.
RSpec.describe DocsKit::McpServer do
  def view_rendering(inner_html)
    Class.new do
      define_method(:call) { "<div id=\"docs-content\">#{inner_html}</div>" }
    end
  end

  def entry(slug:, title:, group:, href:, view_class:)
    Struct.new(:slug, :title, :group, :href, :view_class, keyword_init: true)
          .new(slug:, title:, group:, href:, view_class:)
  end

  def registry(all:)
    Class.new do
      define_singleton_method(:all) { all }
    end
  end

  let(:doc_registry) do
    registry(
      all: [
        entry(slug: "overview", title: "Overview", group: "Guide", href: "/docs/overview",
              view_class: view_rendering("<h2>Setup</h2><p>Install the gem to get started.</p>")),
        entry(slug: "unwritten", title: "Unwritten", group: "Guide", href: "/docs/unwritten", view_class: nil)
      ]
    )
  end

  def configure
    DocsKit.configure do |c|
      c.brand = "Acme Docs"
      c.tagline = "Everything about Acme."
      c.nav_registries = { "Docs" => doc_registry }
    end
    DocsKit.configuration
  end

  # Parse a JSON-RPC response string (what #handle_json returns).
  def rpc(server, method, params = {})
    require "json"
    body = { jsonrpc: "2.0", id: 1, method:, params: }.to_json
    JSON.parse(server.handle_json(body))
  end

  describe ".build" do
    context "when the mcp gem is present" do
      subject(:server) { described_class.build(configure, base_url: "https://acme.dev") }

      before { skip "mcp gem not loaded" unless defined?(MCP) }

      it "returns an MCP::Server" do
        expect(server).to be_a(MCP::Server)
      end

      it "names the server from the brand" do
        expect(server.name).to include("Acme Docs")
      end

      it "resolves a callable brand for the name and instructions" do
        config = configure
        config.brand = -> { "Globex Docs" }
        built = described_class.build(config, base_url: "https://acme.dev")

        expect(built.name).to eq("Globex Docs")
        expect(built.instructions).to include("tools for Globex Docs.")
      end

      it "sets instructions from the tagline and points agents at /llms.txt" do
        expect(server.instructions).to include("Everything about Acme.")
        expect(server.instructions).to include("/llms.txt")
      end

      describe "tools/list" do
        subject(:tool_names) { rpc(server, "tools/list").dig("result", "tools").map { |t| t["name"] } }

        it "advertises exactly the three read-only tools" do
          expect(tool_names).to contain_exactly("list_pages", "get_page", "search_docs")
        end
      end

      describe "tools/call list_pages" do
        subject(:text) do
          rpc(server, "tools/call", { name: "list_pages", arguments: {} })
            .dig("result", "content", 0, "text")
        end

        it "returns the authored pages (unwritten excluded), with absolute urls" do
          expect(text).to include("overview").and include("https://acme.dev/docs/overview")
          expect(text).not_to include("unwritten")
        end
      end

      describe "tools/call get_page" do
        it "returns the page's Markdown twin for a known slug" do
          text = rpc(server, "tools/call", { name: "get_page", arguments: { slug: "overview" } })
                 .dig("result", "content", 0, "text")

          expect(text).to include("Install the gem")
        end

        it "reports not found (listing valid slugs) for an unknown slug" do
          text = rpc(server, "tools/call", { name: "get_page", arguments: { slug: "nope" } })
                 .dig("result", "content", 0, "text")

          expect(text).to include("overview")
        end
      end

      describe "tools/call search_docs" do
        it "returns ranked hits for a query" do
          text = rpc(server, "tools/call", { name: "search_docs", arguments: { query: "install" } })
                 .dig("result", "content", 0, "text")

          expect(text).to include("Overview")
        end
      end
    end

    context "when the mcp gem is absent" do
      it "no-ops (returns nil) rather than raising" do
        allow(described_class).to receive(:mcp_available?).and_return(false)

        expect(described_class.build(configure)).to be_nil
      end
    end
  end
end
