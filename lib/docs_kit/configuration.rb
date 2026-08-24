# frozen_string_literal: true

require_relative "seo_config"
require_relative "landing_config"

module DocsKit
  # Per-site configuration for the shared docs chrome. Everything that differs
  # between two otherwise-identical docs sites lives here, so the Phlex shell
  # (DocsUI::Shell, DocsUI::Sidebar, DocsUI::ThemeSwitcher) is byte-identical across
  # sites and only the config changes.
  #
  #   DocsKit.configure do |c|
  #     c.brand        = "phlex-reactive"
  #     c.title_suffix = "phlex-reactive"
  #     c.themes       = %w[dark light synthwave ...]
  #     c.nav          = -> { { "Demos" => Demo.grouped, "Docs" => Doc.grouped } }
  #   end
  class Configuration
    # The brand text shown in the topbar and sidebar header.
    attr_accessor :brand

    # A one-line site summary, rendered as the llms.txt blockquote
    # (`> {tagline}`) under the H1. Defaults to nil → the blockquote line is
    # omitted, so a site that never sets it still gets a valid llms.txt. Purely
    # for the AI-readable index (DocsKit::LlmsText); the chrome never shows it.
    attr_accessor :tagline

    # The href the topbar brand link points at. Defaults to "/" (site root). A
    # site whose docs live under a subpath sets its own (e.g. "/docs") so the
    # brand link is a one-line config change, not a Shell subclass.
    attr_accessor :brand_href

    # Appended to a page's <title> (e.g. "Installation · phlex-reactive").
    # Defaults to #brand when unset.
    attr_writer :title_suffix

    # The themes offered by the ThemeSwitcher. The first is the page default
    # unless #default_theme is set. Must match the themes enabled in the
    # site's Tailwind @plugin "daisyui" { themes: ... } block.
    attr_accessor :themes

    # The data-theme applied to <html> on first paint. Defaults to the first
    # entry of #themes.
    attr_writer :default_theme

    # A callable returning the sidebar nav as an ordered Hash of
    # { "Heading" => { "Subgroup" => [items] } }. Each item must respond to
    # the duck type the Sidebar renders (see DocsUI::Sidebar#nav_link): #href,
    # #label, and optional #icon. Defaults to an empty nav.
    #
    # Prefer #nav_registries for the common case — an explicit #nav lambda is
    # only needed for bespoke nav (multiple registries interleaved, custom
    # subgroups). When #nav is left at its default, the sidebar derives from
    # #nav_registries instead.
    attr_reader :nav

    # Assigning #nav marks it explicit, so #nav_groups uses it verbatim rather
    # than deriving from #nav_registries — tracked by a flag, not object
    # identity, so ANY assigned lambda wins (even one that resolves to {}).
    def nav=(value)
      @nav_explicit = true
      @nav = value
    end

    # An ordered { "Heading" => registry_class } map. Each registry responds to
    # .nav_items (Registry v2) → { group => [NavItem] } for its authored pages.
    # #nav_groups derives the whole sidebar from this with zero site code, so a
    # site never hand-writes the nav lambda. Defaults to {}. An explicit #nav
    # lambda still wins (full backwards compatibility).
    attr_accessor :nav_registries

    # Optional callable returning a short version-badge string for the sidebar
    # header (e.g. -> { "v#{DaisyUI::VERSION}" }). nil renders no badge.
    attr_accessor :version_badge

    # The stylesheet logical names linked in <head>, in order. Defaults to
    # ["application"] (the Bun/Tailwind-compiled build). A site that ships extra
    # stylesheets (e.g. a separate rouge theme) lists them here.
    attr_accessor :stylesheets

    # The Rouge theme class used by DocsUI::Code for inline syntax-highlight CSS.
    # This is the BASE (light) theme, emitted un-scoped so it applies to every
    # theme unless a dark override wins (see #code_theme_dark).
    attr_accessor :code_theme

    # An optional second Rouge theme (String name or Class) used for the site's
    # DARK daisyUI themes. Default nil → single-theme behavior, fully backwards
    # compatible. When set, DocsUI::Code additionally emits this theme's CSS scoped
    # under [data-theme=X] .code-highlight for each shipped dark theme (see
    # #dark_themes), so code blocks stay readable when the switcher flips to a
    # dark theme — CSS-only, no JS, no flash.
    attr_accessor :code_theme_dark

    # The theme names treated as DARK for #code_theme_dark scoping. Defaults to
    # the built-in daisyUI dark themes (DEFAULT_DARK_THEMES). Intersected with
    # #themes at render time (see #dark_themes_shipped) so only shipped themes
    # generate CSS. Override to name custom dark themes (e.g. %w[zazu-dark]).
    attr_accessor :dark_themes

    # The lucide icon name used for a nav group with no explicit icon.
    attr_accessor :default_group_icon

    # The RailsIcons library docs-kit renders its OWN chrome icons from (the
    # sidebar carets, search glyph, theme toggle, etc.). Defaults to "lucide" to
    # match the lucide icon names docs-kit ships. This is independent of the host
    # app's RailsIcons.configuration.default_library — a host whose default is
    # phosphor/heroicons can leave this at "lucide" so the chrome keeps rendering,
    # without flipping its global default. Set to nil to defer to the host's
    # default_library.
    attr_accessor :icon_library

    # Namespaces the sidebar's localStorage keys (collapse state) so two docs
    # sites on the same origin don't clobber each other. Defaults to a slug of
    # the brand.
    attr_writer :nav_storage_key

    # The default "On this page" (auto-TOC) placement, used by DocsUI::Page when a
    # page doesn't pass its own on_page:. One of the ON_PAGE_MODES, or false to
    # render no auto-TOC by default.
    attr_writer :on_page_default

    # Friendly-name → Rouge lexer aliases for code blocks, merged over the
    # built-in defaults. Any language Rouge knows (~200) already works by its own
    # name/alias; use this only to add or override (e.g. { curl: "console",
    # dockerfile: "docker" }). Value is anything Rouge::Lexer.find accepts.
    attr_accessor :code_lexer_aliases

    # The lexer used when a requested language can't be resolved. Default
    # "plaintext" (no highlighting, never raises).
    attr_accessor :code_lexer_fallback

    # Human labels for language tabs in DocsUI::Example, merged over the built-ins
    # (e.g. { elixir: "Elixir", curl: "cURL" }). Unknown tokens humanize.
    attr_accessor :code_language_labels

    # Whether DocsUI::Page shows the "Markdown" masthead action — a link to the
    # page's `.md` twin that docs-nav enhances into copy-to-clipboard. Defaults to
    # true; set false to hide the affordance site-wide (the `.md` route still
    # works). See DocsKit::MarkdownExport / DocsKit::Controller#render_page.
    attr_accessor :page_markdown_action

    # Whether the built-in read-only MCP endpoint (DocsKit::McpController, a
    # POST /mcp JSON-RPC server exposing list_pages / get_page / search_docs over
    # the same registry the docs render from) is active. Defaults to true, but the
    # endpoint only turns on when the optional `mcp` gem is ALSO present and the
    # host draws the route — #mcp_enabled? gates on both. Set false to keep the
    # endpoint off even on a site that bundles the gem. See DocsKit::McpServer.
    attr_accessor :mcp

    # Whether the topbar renders the docs-search form (and the docs-nav palette
    # markup). Defaults to true. Set false to hide search site-wide — the route
    # can stay drawn, but no affordance points at it. Gated together with a
    # present #search_path by #search_enabled?, which the Shell reads.
    attr_accessor :search

    # The path the topbar search form submits to (GET ?q=), and the base the
    # palette fetches `.json` from. Defaults to "/docs/search" — the route the
    # install generator draws. A site that mounts search elsewhere sets its own;
    # blank it to disable the affordance without touching #search.
    attr_accessor :search_path

    # The keyboard shortcut STRINGS that open the search palette, e.g.
    # %w[/ mod+k s]. Defaults to DEFAULT_SEARCH_SHORTCUTS (["/", "mod+k"] — the
    # keys shipped before this was configurable, so existing sites are unchanged).
    # "mod" is the platform modifier (⌘ on mac, Ctrl elsewhere), so one entry
    # works on every OS. Read the parsed form via #search_shortcuts (which maps to
    # DocsKit::Shortcut and drops anything unparseable), never @search_shortcuts.
    attr_writer :search_shortcuts

    # The API base URL prefixed onto a DocsUI::RequestExample path so copy-pasted
    # snippets point at a real host. Defaults to a neutral example host; a site
    # sets its own (e.g. "https://api.acme.com").
    attr_accessor :api_base_url

    # An example Authorization header line merged into every generated request
    # snippet (e.g. "Authorization: Bearer sk_live_..."). Defaults to nil → no
    # auth line, so a site with no auth example renders clean snippets.
    attr_accessor :api_auth_header

    # Site overrides/extensions for the DocsUI::RequestExample client tabs — an
    # ordered { token => DocsKit::ApiClient } Hash merged OVER the four shipped
    # defaults (curl, javascript, ruby, python). Reusing a default token replaces
    # that client (SDK-flavored snippet); a new token appends a tab (e.g. a `cli`).
    # Read the effective map via #api_clients (which merges), never @api_clients.
    attr_writer :api_clients

    # The opt-in "App Home" link — the way back to the application that hosts
    # the docs, rendered ONCE in the topbar right after the brand (e.g.
    # "Back to the app" on a docs site embedded in a bigger app). A Hash
    # ({ href:, label: }) or a DocsKit::TopbarLink; #app_link normalizes it.
    # Defaults to nil → no link renders and the topbar is byte-identical to
    # before. Distinct from #brand_href, which is the DOCS home (the brand,
    # sidebar, and page-masthead links). Read via #app_link, never @app_link.
    attr_writer :app_link

    # The opt-in shell brand mark, rendered by BOTH the topbar and the sidebar
    # header in place of the text #brand (which stays the accessible-name
    # fallback). A Hash in exactly one of the DocsKit::BrandLogo forms —
    # svg:/paths: (inline path-d, theme-adaptive via currentColor), markup:/file:
    # (site-authored <svg> embedded verbatim), or src: (an <img>, NOT
    # theme-adaptive) — or an already-built BrandLogo. Defaults to nil → the
    # text brand renders and the chrome is byte-identical to before. Sibling of
    # c.landing.logo, which is the landing-hero mark. Read via #brand_logo,
    # never @brand_logo.
    def brand_logo=(value)
      @brand_logo = nil
      @brand_logo_raw = value
    end

    # Where the topbar renders the brand: :always (the default — byte-compat),
    # or :mobile_only, which hides it at the drawer-pinned breakpoint (lg:)
    # where the sidebar brand is already visible, deduplicating the mark.
    attr_reader :topbar_brand

    # The topbar-brand placements. At lg: the sidebar (with its own brand) is
    # pinned open, so :mobile_only drops the duplicate; :always keeps it.
    TOPBAR_BRAND_MODES = %i[always mobile_only].freeze

    def topbar_brand=(value)
      mode = value.respond_to?(:to_sym) ? value.to_sym : value
      unless TOPBAR_BRAND_MODES.include?(mode)
        raise ArgumentError,
              "topbar_brand must be one of #{TOPBAR_BRAND_MODES.inspect} (got #{value.inspect})"
      end

      @topbar_brand = mode
    end

    # External links rendered in the topbar next to the theme switcher — a repo
    # link, a chat invite, a social profile. Each entry is a Hash
    # ({ href:, label:, icon: }) or a DocsKit::TopbarLink; #topbar_links
    # normalizes them into TopbarLink value objects. Defaults to [] → the topbar
    # is byte-identical to before, so a site that sets nothing is unchanged.
    # `icon` is a shipped brand mark (:github, :discord, …) or a lucide icon
    # name. Read the normalized list via #topbar_links, never @topbar_links.
    attr_writer :topbar_links

    # The OpenAPI spec the `operation` page helper / DocsUI::OpenApiOperation read
    # from: a String/Pathname path (`.json` parsed as JSON, else YAML) or an
    # already-parsed Hash. Defaults to nil → the bridge is off and a site that
    # doesn't set it is byte-identical to before. Read the loaded model via
    # #openapi_document (which memoizes + reloads on file change), never @openapi.
    attr_accessor :openapi

    # The documentation versions this site serves — a list of Hashes
    # ({ id:, label:, ref:, current:, noindex: }) or DocsKit::DocVersion objects;
    # #versions normalizes them. Defaults to [] → versioning is off and the site
    # is byte-identical to before. The `current` entry keeps serving unprefixed
    # at /docs; every other entry serves a committed Markdown snapshot at
    # /<id>/docs (see DocsKit::Snapshot). A version id must match v?\d+(\.\d+)*
    # so the host's static version route constraint recognizes it. Read via
    # #versions, never @versions.
    attr_writer :versions

    # The site's source repository root (e.g. "https://github.com/me/repo"),
    # used for the GitHub compare link between two versions' refs
    # (#compare_url). Defaults to nil → no compare link renders.
    attr_accessor :repo_url

    # Where committed version snapshots live. Defaults to nil, which the reader
    # resolves to Rails.root/"docs_snapshots" under Rails (nil outside Rails —
    # the standalone suite points at fixtures explicitly). Read via
    # #snapshots_path, never @snapshots_path.
    attr_writer :snapshots_path

    # The sentinel "no explicit nav" lambda. #nav_groups compares against this
    # identity to decide whether to derive the sidebar from #nav_registries.
    DEFAULT_NAV = -> { {} }

    # The search-palette shortcuts before this was configurable — "/" and the
    # platform command chord — so a site that never sets #search_shortcuts keeps
    # exactly the previous behavior.
    DEFAULT_SEARCH_SHORTCUTS = ["/", "mod+k"].freeze

    # The built-in daisyUI theme names that are dark. #dark_themes defaults to
    # this; #dark_themes_shipped intersects it with the site's #themes so only
    # shipped themes ever generate dark code CSS. A site with custom dark themes
    # overrides #dark_themes (docs-kit can't see the compiled daisyUI CSS to
    # detect darkness at render time, so an honest static list + override wins).
    DEFAULT_DARK_THEMES = %w[
      dark synthwave halloween forest black luxury dracula
      business night coffee dim sunset abyss
    ].freeze

    # Built-in friendly aliases (kept small — Rouge resolves most names itself).
    DEFAULT_LEXER_ALIASES = { curl: "console", console: "console" }.freeze

    # Built-in tab labels for the common languages that don't just capitalize.
    DEFAULT_LANGUAGE_LABELS = {
      javascript: "JavaScript", typescript: "TypeScript", php: "PHP",
      curl: "cURL", json: "JSON", yaml: "YAML", html: "HTML", css: "CSS",
      erb: "ERB", jsx: "JSX", tsx: "TSX", sql: "SQL", graphql: "GraphQL"
    }.freeze

    def initialize
      @brand = "Docs"
      @tagline = nil
      @brand_href = "/"
      @title_suffix = nil
      @themes = %w[dark light]
      @default_theme = nil
      # The default nav lambda. Until a site assigns #nav (which sets
      # @nav_explicit), #nav_groups treats nav as "unset" and derives the sidebar
      # from #nav_registries instead; an explicit c.nav (any lambda) then wins.
      @nav = DEFAULT_NAV
      @nav_explicit = false
      @nav_registries = {}
      @version_badge = nil
      @stylesheets = %w[application]
      @code_theme = "Rouge::Themes::Monokai"
      @code_theme_dark = nil
      @dark_themes = DEFAULT_DARK_THEMES
      @default_group_icon = "file-text"
      @icon_library = "lucide"
      @nav_storage_key = nil
      @on_page_default = :panel
      @code_lexer_aliases = {}
      @code_lexer_fallback = "plaintext"
      @code_language_labels = {}
      @page_markdown_action = true
      @mcp = true
      @search = true
      @search_path = "/docs/search"
      @search_shortcuts = DEFAULT_SEARCH_SHORTCUTS
      @api_base_url = "https://api.example.com"
      @api_auth_header = nil
      @api_clients = {}
      @app_link = nil
      @topbar_links = []
      @openapi = nil
      @brand_logo = nil
      @brand_logo_raw = nil
      @topbar_brand = :always
      @versions = []
      @repo_url = nil
      @snapshots_path = nil
    end

    # The normalized App Home link (a DocsKit::TopbarLink), or nil when unset —
    # absent config, absent link, exactly like every other opt-in knob.
    def app_link
      return if @app_link.nil?

      DocsKit::TopbarLink.from(@app_link)
    end

    # The normalized shell brand mark (a DocsKit::BrandLogo), or nil when unset.
    # Memoized (and invalidated on reassignment) — unlike #app_link's rebuild-
    # per-read, because a file: mark shape-checks and reads its SVG on build;
    # per-render re-normalization would repeat that IO. A malformed value raises
    # here, on first read — loud, never a silently broken header.
    def brand_logo
      return if @brand_logo_raw.nil?

      @brand_logo ||= DocsKit::BrandLogo.from(@brand_logo_raw)
    end

    # The normalized topbar links (DocsKit::TopbarLink list), in declaration
    # order. Each configured Hash/TopbarLink is coerced via TopbarLink.from, so
    # the Shell only ever sees value objects. Blank/nil config yields [].
    def topbar_links
      Array(@topbar_links).map { |link| DocsKit::TopbarLink.from(link) }
    end

    # The normalized version list (DocsKit::DocVersion list), in declaration
    # order. Each configured Hash/DocVersion is coerced via DocVersion.from, so
    # the switcher and the snapshot reader only ever see value objects.
    # Blank/nil config yields [].
    def versions
      Array(@versions).map { |version| DocsKit::DocVersion.from(version) }
    end

    # The version serving unprefixed at /docs: the entry marked current: true,
    # else the first configured entry, else nil (an unversioned site).
    def current_version
      versions.find(&:current?) || versions.first
    end

    # The configured version with this id, or nil when unknown (or nil id).
    def version(id)
      return if id.nil?

      versions.find { |version| version.id.to_s == id.to_s }
    end

    # The version a request's :version param resolves to: the strict #version
    # lookup, falling back to #current_version for an unknown or missing id —
    # one rule shared by DocsKit::Controller#render_page and the gem's own
    # controllers (DocsKit::Scoping), so a bad param degrades to the current
    # docs instead of 500ing.
    def resolve_version(id)
      version(id) || current_version
    end

    # Whether the version chrome (switcher, llms.txt Versions block) renders.
    # A single configured version is not worth a switcher, so this needs two —
    # and an unconfigured site stays byte-identical to before.
    def versioning_enabled?
      versions.size > 1
    end

    # The resolved snapshots directory: the configured value verbatim, else
    # Rails.root/"docs_snapshots" under Rails, else nil (no Rails, no default —
    # the standalone suite passes explicit paths).
    def snapshots_path
      return @snapshots_path if @snapshots_path

      Rails.root.join("docs_snapshots") if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
    end

    # The GitHub compare URL between two versions' refs
    # ("{repo_url}/compare/{from.ref}...{to.ref}"), or nil unless #repo_url and
    # BOTH refs are present — absent value, absent link, never a broken one.
    def compare_url(from, to)
      return if repo_url.nil? || from&.ref.nil? || to&.ref.nil?

      "#{repo_url.chomp('/')}/compare/#{from.ref}...#{to.ref}"
    end

    # The SEO / social-share knobs (DocsKit::SeoConfig), read by DocsUI::MetaTags.
    # Lazily built and memoized so a `c.seo.description = ...` block mutates the
    # one instance the Shell later reads. A site that never touches it gets the
    # backwards-safe defaults (see SeoConfig), so the head is a strict superset of
    # the pre-SEO markup.
    def seo
      @seo ||= DocsKit::SeoConfig.new
    end

    # The landing-page knobs (DocsKit::LandingConfig), read by DocsUI::Landing.
    # Lazily built and memoized so a `c.landing.title = ...` block mutates the one
    # instance the component later reads. A site that never touches it still gets a
    # minimal hero + the doc index (see LandingConfig), so DocsUI::Landing is safe
    # to render with zero landing config.
    def landing
      @landing ||= DocsKit::LandingConfig.new
    end

    # The loaded DocsKit::OpenApi::Document for #openapi. Memoized; when #openapi
    # is a file path, the memo is invalidated on an mtime change so editing the
    # spec in development is picked up without a server restart. Raises a
    # DocsKit::Error naming the knob when read while #openapi is unset — a missing
    # spec has nothing useful to degrade to.
    def openapi_document
      raise DocsKit::Error, "no OpenAPI spec configured — set c.openapi to a path or Hash" if @openapi.nil?

      mtime = openapi_source_mtime
      return @openapi_document if defined?(@openapi_document) && @openapi_document_mtime == mtime

      @openapi_document_mtime = mtime
      @openapi_document = DocsKit::OpenApi.load(@openapi)
    end

    # The effective client map for DocsUI::RequestExample: the four shipped
    # defaults with site overrides/extensions merged over them. Hash#merge keeps
    # a reused token in its original position and appends new tokens in
    # declaration order, so tab order is stable and predictable.
    def api_clients
      DocsKit::ApiClient::DEFAULTS.merge(@api_clients || {})
    end

    # The effective alias map (built-ins + site overrides), symbol-keyed.
    def lexer_aliases
      DEFAULT_LEXER_ALIASES.merge((@code_lexer_aliases || {}).transform_keys(&:to_sym))
    end

    # The effective label map (built-ins + site overrides), symbol-keyed.
    def language_labels
      DEFAULT_LANGUAGE_LABELS.merge((@code_language_labels || {}).transform_keys(&:to_sym))
    end

    # The auto-TOC placements, all driven by the same docs-nav Stimulus
    # controller (it reads the page's headings from the DOM):
    #   :panel   — a sticky card in the top-right of the content column
    #   :toggle  — a sticky floating button (top-right) opening a dropdown
    #   :sidebar — nested under the active nav item in the left sidebar
    ON_PAGE_MODES = %i[panel toggle sidebar].freeze

    # The resolved default placement (a mode symbol or false). A bare `true`
    # default means :panel (the canonical default), never a self-reference.
    def on_page_default
      raw = @on_page_default
      raw = :panel if raw == true
      coerce_on_page_mode(raw)
    end

    # Coerce a per-page on_page: value to a valid mode symbol or false. `true`
    # means "use the configured default".
    def normalize_on_page(value)
      return on_page_default if value == true

      coerce_on_page_mode(value)
    end

    private

    # True when the optional `mcp` gem can be loaded. Memoized across both
    # outcomes so a site without the gem doesn't pay a failed require per request.
    # We attempt the require lazily (rather than only checking defined?(MCP)) so a
    # bundled-but-not-yet-required gem still counts as present — the same
    # degrade-gracefully-on-a-missing-optional-gem posture as DocsUI::Icon's
    # rails_icons guard.
    def mcp_gem_present?
      return @mcp_gem_present if defined?(@mcp_gem_present)

      @mcp_gem_present =
        begin
          require "mcp"
          defined?(::MCP::Server) ? true : false
        rescue LoadError
          false
        end
    end

    # The mtime of the #openapi source when it's a readable file path, else nil
    # (a Hash spec, or a path that isn't a file). Drives #openapi_document's
    # reload-on-change memoization; a Hash spec loads once and never invalidates.
    def openapi_source_mtime
      return if @openapi.is_a?(Hash)

      path = Pathname.new(@openapi)
      path.file? ? path.mtime : nil
    rescue StandardError
      nil
    end

    # { heading => registry.nav_items }, dropping headings with no authored
    # pages so the sidebar never shows an empty group.
    def nav_groups_from_registries
      @nav_registries.each_with_object({}) do |(heading, registry), acc|
        items = registry.nav_items
        acc[heading] = items unless items.empty?
      end
    end

    def coerce_on_page_mode(value)
      case value
      when false, nil then false
      when *ON_PAGE_MODES then value.to_sym
      else
        raise ArgumentError,
              "on_page must be one of #{ON_PAGE_MODES.inspect}, true, or false (got #{value.inspect})"
      end
    end

    public

    def nav_storage_key
      @nav_storage_key || @brand.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end

    def title_suffix
      @title_suffix || @brand
    end

    # Whether the built-in MCP endpoint is active: the #mcp toggle is on AND the
    # optional `mcp` gem is loadable — the same "toggle AND capability" shape as
    # #search_enabled?. Read by DocsKit::LlmsText (to advertise /mcp in llms.txt)
    # and DocsKit::McpController (to 404 when off), so a site without the gem, or
    # one that set c.mcp = false, is byte-identical to before this feature.
    def mcp_enabled?
      !!@mcp && mcp_gem_present?
    end

    # Whether the Shell renders the search affordance: search is on AND a path is
    # set to submit to. A site with @search_path blanked (or nil) gets no form
    # even if @search is true — there'd be nothing to submit to.
    def search_enabled?
      !!@search && !@search_path.to_s.empty?
    end

    # The parsed search-palette shortcuts (DocsKit::Shortcut list), with anything
    # unparseable dropped. The topbar renders one <kbd> per entry and docs-nav
    # binds each; an empty list means no keyboard shortcut (the form still works).
    def search_shortcuts
      DocsKit::Shortcut.parse_list(@search_shortcuts)
    end

    def default_theme
      @default_theme || Array(@themes).first
    end

    # The resolved nav Hash for this request. Always returns a Hash.
    #
    # An ARCHIVED version in DocsKit::Scope wins outright: the sidebar derives
    # from that version's snapshot manifest (hrefs already version-prefixed), so
    # an archived page never links into the live docs — even a site's explicit
    # #nav lambda describes the live pages, not the frozen ones. With no scope
    # (or the current version) nothing changes: an explicit #nav lambda wins,
    # else the sidebar derives from #nav_registries — each heading maps to its
    # registry's .nav_items, and a heading whose pages are all unauthored
    # (empty nav_items) is dropped so no empty group renders.
    def nav_groups
      scope_version = DocsKit::Scope.version
      return DocsKit::Snapshot.for(scope_version, config: self).nav_groups if scope_version&.archived?
      return nav_groups_from_registries unless @nav_explicit

      result = @nav.respond_to?(:call) ? @nav.call : @nav
      result || {}
    end

    # The resolved version badge string, or nil.
    # The rendered version badge. A callable is invoked; a plain String (or any
    # non-nil value) is coerced to its string form — so `c.version_badge = "v1.2"`
    # renders, not only a lambda.
    def version_badge_text
      return if @version_badge.nil?
      return @version_badge.call if @version_badge.respond_to?(:call)

      @version_badge.to_s
    end

    # The default Rouge theme both #code_theme_class and #code_theme_dark_class
    # fall back to when a configured theme name can't be resolved — so a typo'd
    # theme name degrades gracefully instead of raising on every code block.
    DEFAULT_CODE_THEME = "Rouge::Themes::Monokai"

    # The Rouge theme class resolved from #code_theme (String or class). A String
    # name that doesn't resolve degrades to the default theme rather than raising
    # NameError on every DocsUI::Code render.
    def code_theme_class
      return @code_theme if @code_theme.is_a?(Class)

      resolve_theme(@code_theme) || Object.const_get(DEFAULT_CODE_THEME)
    end

    # The dark Rouge theme class resolved from #code_theme_dark (String or
    # class), or nil when unset — mirrors #code_theme_class. DocsUI::Code emits
    # dark code CSS only when this is non-nil, so an unresolvable name degrades to
    # nil (no dark restyle) rather than raising.
    def code_theme_dark_class
      return if @code_theme_dark.nil?
      return @code_theme_dark if @code_theme_dark.is_a?(Class)

      resolve_theme(@code_theme_dark)
    end

    # The dark themes the site actually ships: #dark_themes intersected with
    # #themes, in #themes declaration order. DocsUI::Code scopes the dark theme's
    # CSS under [data-theme=X] for each of these, so a dark theme that isn't in
    # the Tailwind build never emits dead CSS.
    def dark_themes_shipped
      Array(@themes) & Array(@dark_themes)
    end

    private

    # Resolve a Rouge theme constant from its String name, returning nil (not
    # raising) when the name doesn't resolve — a typo'd or unloaded theme must
    # not crash every code block on the page.
    def resolve_theme(name)
      Object.const_get(name.to_s)
    rescue NameError
      nil
    end
  end
end
