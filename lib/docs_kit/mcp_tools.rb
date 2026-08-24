# frozen_string_literal: true

require "cgi"

module DocsKit
  # The pure, HTTP-free core the built-in MCP server exposes — three plain-Ruby
  # functions over the SAME registry, Markdown twins, and search index the docs
  # already render from, so an agent queries live docs, never a stale scrape:
  #
  #   list_pages(config)         → [{ slug, title, group, url }]           authored pages only
  #   get_page(config, slug:)    → { found:, title:, url:, markdown: } | { found: false, message: }
  #   search_docs(config, query:)→ [{ page_title, section_title, url, snippet }]  ranked
  #
  # Zero `mcp`-gem dependency and zero JSON-RPC: DocsKit::McpServer wraps these
  # into MCP tools, and the controller only threads the Rails view context (for
  # url helpers/CSRF, the same seam DocsKit::LlmsController#full uses). So the
  # whole consumption story is unit-testable without booting Rails or the SDK.
  #
  # "Authored" means a resolvable #view_class — DocsKit::LlmsText.pages already
  # flattens every registry to just those, so an unwritten page is never listed,
  # fetched, or indexed (no dead links, no 404s over the protocol).
  module McpTools
    module_function

    # The authored pages across every registry, in config/registry order, as a
    # flat list of { slug, title, group, url } — url absolutized against base_url
    # when given (agents fetch a portable URL), else the root-relative href.
    def list_pages(config, base_url: nil)
      LlmsText.pages(config).map do |page|
        {
          slug: page.slug,
          title: page.title,
          group: page.group,
          url: absolutize(page.href, base_url)
        }
      end
    end

    # A single page's Markdown twin by slug. Renders the page's #view_class
    # through view_context (nil off-Rails) exactly as LlmsController#full does. An
    # unknown or unwritten slug returns { found: false } with a message listing
    # the valid slugs, so an agent can correct itself instead of hitting an error.
    def get_page(config, slug:, base_url: nil, view_context: nil)
      page = find_page(config, slug)
      return not_found(config, slug) unless page

      {
        found: true,
        slug: page.slug,
        title: page.title,
        url: absolutize(page.href, base_url),
        markdown: render_markdown(page, base_url:, view_context:)
      }
    end

    # The top DocsKit::SearchIndex hits for query, as { page_title, section_title,
    # url, snippet } — url absolutized, snippet reduced to plain text (the index's
    # HTML <mark> highlight stripped, since MCP delivers text, not HTML). Blank
    # query → []. Builds the index from the same twins search + llms-full serve.
    def search_docs(config, query:, base_url: nil, view_context: nil)
      index_for(config, base_url:, view_context:).search(query).map do |hit|
        {
          page_title: hit.page_title,
          section_title: hit.section_title,
          url: absolutize(hit.href, base_url),
          snippet: strip_html(hit.snippet)
        }
      end
    end

    # The authored page with this slug across every registry, or nil (an unwritten
    # page has no resolvable view_class, so it's absent from LlmsText.pages).
    def find_page(config, slug)
      LlmsText.pages(config).find { |page| page.slug.to_s == slug.to_s }
    end

    # A { found: false } result whose message names every valid slug, so an agent
    # that guessed wrong can retry with a real one.
    def not_found(config, slug)
      valid = list_pages(config).map { |page| page[:slug] }
      {
        found: false,
        slug: slug,
        message: "No page with slug #{slug.inspect}. Valid slugs: #{valid.join(', ')}."
      }
    end

    # A page's GFM Markdown twin, rendered through the view context so url helpers
    # and relative-link absolutization resolve — the LlmsController#full seam.
    # renderable_for is the live-or-snapshot shim (see LlmsText.renderable_for).
    def render_markdown(page, base_url:, view_context:)
      MarkdownExport.new(LlmsText.renderable_for(page), view_context:, base_url:).to_md
    end

    # A DocsKit::SearchIndex over every authored page's twin — the same triples
    # DocsKit::SearchController builds, so MCP search can't drift from the pages.
    def index_for(config, base_url:, view_context:)
      triples = LlmsText.pages(config).map do |page|
        [page.title, page.href, render_markdown(page, base_url:, view_context:)]
      end
      SearchIndex.new(triples)
    end

    # href absolutized against base_url (no .md suffix — MCP serves the page URL,
    # not the twin). Relative href when base_url is nil. Mirrors LlmsText.md_url.
    def absolutize(href, base_url)
      return href unless base_url

      "#{base_url.chomp('/')}#{href}"
    end

    # Reduce the search index's HTML-safe snippet (term wrapped in <mark>, rest
    # CGI-escaped) to plain text: drop the <mark> tags and unescape entities, so
    # the MCP snippet is human/agent-readable text rather than HTML.
    def strip_html(snippet)
      CGI.unescapeHTML(snippet.to_s.gsub(%r{</?mark>}, ""))
    end
  end
end
