# frozen_string_literal: true

module DocsKit
  # Builds the two AI-readable artifacts a docs-kit site serves, straight from
  # the registry — zero authoring:
  #
  #   /llms.txt      — the llmstxt.org index: H1 brand, `> tagline` blockquote,
  #                    one `## {group}` section per nav group, and a
  #                    `- [title](abs .md url)` line per authored page.
  #   /llms-full.txt — every page's Markdown twin concatenated, `# {title}` +
  #                    body, separated by `---`.
  #
  # It's a pure text builder: given a DocsKit::Configuration and (for the full
  # form) already-rendered `[title, markdown]` pairs, it produces strings with no
  # Rails. The controller owns the Rails view context — it renders each page to
  # Markdown (DocsKit::MarkdownExport) and hands the pairs to .full — so all the
  # shaping is unit-testable without booting Rails.
  #
  # The enumeration source is DocsKit::Registry v2: each registry in
  # `config.nav_registries` responds to #nav_items ({ group => [NavItem] },
  # authored pages only) for the index and #all (entries with #view_class) for
  # the authored page list. An unwritten page (no resolvable view_class) is
  # excluded from both, so neither artifact ever links or concatenates a page
  # that doesn't exist yet.
  module LlmsText
    module_function

    # The llms.txt index string. base_url absolutizes each page's `.md` href so
    # agent tooling fetches a portable URL; omit it for relative links.
    #
    # Blocks (H1, the tagline blockquote, and one per section) are separated by a
    # blank line; within a section the `## heading` and its `- [..]` bullets are a
    # single tight list (no blank lines between bullets), per the llmstxt.org
    # convention.
    def index(config, base_url: nil)
      blocks = ["# #{config.brand}"]
      tagline = config.tagline
      blocks << "> #{tagline}" if tagline && !tagline.to_s.empty?
      blocks.concat(section_blocks(config, base_url))

      # Advertise the built-in MCP endpoint last, so an agent that reads llms.txt
      # discovers it can also connect over the protocol (native tools vs fetching
      # text). Only when the endpoint is actually live (gem present + c.mcp on).
      blocks << mcp_block(base_url) if config.mcp_enabled?

      blocks.join("\n\n")
    end

    # One `## {group}` block per nav group, each a tight bullet list of its
    # authored pages' `.md` links, in registry order.
    def section_blocks(config, base_url)
      groups(config).map do |group, links|
        ["## #{group}", *links.map { |link| link_line(link, base_url) }].join("\n")
      end
    end

    # The authored pages for one version of the docs, in config/registry order —
    # each responds to #title / #href / #view_class (render via .renderable_for).
    # This is the ONE enumeration seam every AI surface funnels through, so
    # making IT version-aware makes llms-full.txt, search, and MCP follow the
    # request's version for free.
    #
    # version: nil resolves through DocsKit::Scope (set per request by the
    # controllers), then config.current_version — so an unversioned site, or the
    # current version, enumerates the live registries exactly as before. An
    # ARCHIVED version enumerates its Markdown snapshot instead
    # (DocsKit::Snapshot — every entry is authored by definition).
    def pages(config, version: nil)
      version ||= DocsKit::Scope.version || config.current_version
      return snapshot_pages(config, version) if version&.archived?

      config.nav_registries.values.flat_map { |registry| registry.all.select(&:view_class) }
    end

    # An archived version's pages, from its committed snapshot. Every entry has
    # a view_class by construction; the select keeps the authored-pages contract
    # symmetric with the live branch.
    def snapshot_pages(config, version)
      DocsKit::Snapshot.for(version, config: config).all.select(&:view_class)
    end

    # The Phlex renderable for a page returned by .pages: the page's own
    # #renderable (Registry v2 Entry, Snapshot::Entry) with a backwards-
    # compatible fallback to view_class.new for a site's custom `entries`-style
    # registry class that predates #renderable. The ONE shim — the controllers
    # and MCP tools all call this rather than repeating the respond_to? check.
    def renderable_for(page)
      page.respond_to?(:renderable) ? page.renderable : page.view_class.new
    end

    # The llms-full.txt body: each [title, markdown] pair as `# {title}` + body,
    # separated by a `---` rule. Empty pairs → "".
    def full(_config, title_markdown_pairs)
      title_markdown_pairs.map { |title, markdown| "# #{title}\n\n#{markdown}" }.join("\n\n---\n\n")
    end

    # { group => [links] } across every registry's #nav_items, in config order.
    # A registry with no authored pages contributes nothing, so no empty section
    # is ever emitted.
    def groups(config)
      config.nav_registries.values.each_with_object({}) do |registry, acc|
        registry.nav_items.each { |group, links| (acc[group] ||= []).concat(links) }
      end
    end

    # The `## MCP` section pointing an agent at the read-only MCP endpoint. The
    # `/mcp` URL is absolutized against base_url when available (agents connect to
    # a portable URL); relative otherwise.
    def mcp_block(base_url)
      url = base_url ? "#{base_url.chomp('/')}/mcp" : "/mcp"
      "## MCP\n" \
        "This documentation is also available over the Model Context Protocol " \
        "(search, page retrieval) at #{url} — add it to an MCP client " \
        "(Claude Code, Claude.ai, Cursor) to query these docs as tools."
    end

    # `- [label](absolute .md url)`. The `.md` suffix targets the page's Markdown
    # twin (DocsKit::Controller#render_page).
    def link_line(link, base_url)
      "- [#{link.label}](#{md_url(link.href, base_url)})"
    end

    # href + ".md", absolutized against base_url when given. base_url has no
    # trailing slash concerns here (hrefs are root-relative like "/docs/x").
    def md_url(href, base_url)
      path = "#{href}.md"
      return path unless base_url

      "#{base_url.chomp('/')}#{path}"
    end
  end
end
