# frozen_string_literal: true

module DocsUI
  # The site shell — the full HTML document. A Phlex layout built on the daisyUI
  # Drawer: a sticky topbar, a sidebar always visible on desktop (lg:drawer-open)
  # that toggles as an overlay on mobile, and the page content in a scrollable
  # main. Loads Turbo + (when present) the phlex-reactive Stimulus controller via
  # the importmap tags, and the daisyUI-compiled Tailwind build.
  #
  # Shell IS the full <html> document, so controllers render the page view with
  # `layout: false` (see DocsKit::Controller#render_page) to avoid double <html>
  # nesting. phlex-rails still renders through a real view context, so CSRF,
  # dom_id, url helpers, and the reactive token signer all work inside components.
  #
  #   render DocsUI::Shell.new(title: "Installation") { page_body }
  class Shell < Phlex::HTML
    include Phlex::Rails::Helpers::CSRFMetaTags
    include Phlex::Rails::Helpers::CSPMetaTag
    include Phlex::Rails::Helpers::ContentSecurityPolicyNonce
    include Phlex::Rails::Helpers::StylesheetLinkTag
    include Phlex::Rails::Helpers::JavaScriptImportmapTags
    include DaisyUI

    DRAWER_ID = "site-drawer"

    # title:       the page title → <title> and og:title.
    # description: the page description → the SEO/social meta tags (DocsUI::Page
    #              passes its own description or #lead); nil falls back to
    #              config.seo.description in DocsUI::MetaTags.
    # on_page:     the auto-TOC placement for this page (:panel/:toggle/:sidebar or
    #              false). Threaded to the sidebar's docs-nav controller;
    #              :panel/:toggle also render an "On this page" slot in the content.
    def initialize(title: nil, description: nil, on_page: false)
      @title = title
      @description = description
      @on_page = DocsKit.configuration.normalize_on_page(on_page)
    end

    def view_template(&)
      doctype
      html(lang: "en", data: { theme: config.default_theme }) do
        render_head
        # The docs-nav controller lives on <body> — the shared ancestor of BOTH
        # the sidebar (collapse persistence, :sidebar TOC injection) and the
        # content column (:panel/:toggle TOC slot + scroll-spy). Scoping it to the
        # sidebar alone would put the content-column TOC out of its reach.
        body(
          class: "bg-base-100 text-base-content",
          data: {
            controller: "docs-nav",
            docs_nav_storage_key_value: config.nav_storage_key,
            docs_nav_on_page_value: (@on_page || "").to_s
          }
        ) do
          shell(&)
        end
      end
    end

    private

    def config = DocsKit.configuration

    # The request's CSP nonce, or nil when there's no Rails view context (an
    # isolated Phlex render, or a host that doesn't nonce script-src). The
    # phlex-rails value helper delegates to view_context, which raises without
    # one, so guard on its presence — a nil result makes Phlex omit the
    # attribute, keeping the un-nonced markup unchanged.
    def csp_nonce = view_context && content_security_policy_nonce

    # panel/toggle render their TOC in the content column; sidebar mode is
    # injected by the controller under the active nav link (no content slot).
    def content_toc? = %i[panel toggle].include?(@on_page)

    def render_head
      head do
        title { [@title, config.title_suffix].compact.join(" · ") }
        meta(charset: "utf-8")
        meta(name: "viewport", content: "width=device-width,initial-scale=1")
        # SEO / social-share tags (description, Open Graph, Twitter Card,
        # canonical, favicon, robots, theme-color) from config.seo + this page's
        # title/description. A site that sets no c.seo still gets a valid minimal
        # OG block, so the head is a strict superset of the pre-SEO markup.
        render DocsUI::MetaTags.new(title: @title, description: @description)
        csrf_meta_tags
        csp_meta_tag
        # Turbo morphs page-level navigations so a re-render preserves scroll and
        # focus, matching the in-place feel of reactive components.
        meta(name: "turbo-refresh-method", content: "morph")
        meta(name: "turbo-refresh-scroll", content: "preserve")
        config.stylesheets.each { |sheet| stylesheet_link_tag(sheet, data: { turbo_track: "reload" }) }
        theme_restore_script
        javascript_importmap_tags
      end
    end

    # Restore the persisted theme BEFORE first paint so there's no flash of the
    # server default before the docs-nav controller runs. Reads the same
    # localStorage key the controller writes (docs-kit:<site>:theme). Runs on
    # initial load and on Turbo page renders (turbo:load).
    #
    # Carries the request's CSP nonce so the inline script is allowed under a
    # nonce-based script-src (Rails' default when script-src is in
    # content_security_policy_nonce_directives). Off a request there is no nonce
    # (see #csp_nonce) and Phlex omits a nil-valued attribute, so the no-nonce
    # markup is byte-identical to before.
    def theme_restore_script
      key = "docs-kit:#{config.nav_storage_key}:theme"
      script(nonce: csp_nonce) do
        raw(safe(<<~JS))
          (function(){
            function apply(){
              try{
                var t = localStorage.getItem(#{key.to_json});
                if (t) document.documentElement.setAttribute("data-theme", t);
              }catch(e){}
            }
            apply();
            document.addEventListener("turbo:load", apply);
          })();
        JS
      end
    end

    # The daisyUI Drawer app-shell. Desktop: sidebar always open (lg:drawer-open).
    # Mobile: sidebar hidden, toggled by the hamburger in the topbar.
    def shell(&block)
      Drawer(id: DRAWER_ID, class: "lg:drawer-open min-h-screen") do |drawer|
        drawer.toggle

        drawer.content(class: "flex flex-col min-h-screen") do
          topbar
          main(class: "flex-1 overflow-auto px-4 py-8 md:px-8") do
            # The :panel/:toggle "On this page" is position:fixed to the viewport's
            # top-right (below the topbar), so it never overlaps the prose. Render
            # it here so it's inside the docs-nav controller scope; the controller
            # fills it from the page headings.
            render DocsUI::OnThisPage.new(mode: @on_page) if content_toc?
            # id="docs-content" is the stable extraction anchor for the Markdown
            # export (DocsKit::MarkdownExport walks this subtree). The topbar,
            # sidebar, and TOC live OUTSIDE it, so they never bleed into the .md.
            div(id: "docs-content", class: "mx-auto max-w-4xl", &block)
          end
        end

        drawer.side(class: "z-40") do
          drawer.overlay
          render DocsUI::Sidebar.new
        end
      end
    end

    # Sticky topbar: hamburger (mobile only), brand, search, theme switcher.
    def topbar
      div(class: "navbar bg-base-200 border-b border-base-300 sticky top-0 z-30 px-4") do
        div(class: "flex-1 items-center gap-2") do
          label(for: DRAWER_ID, class: "btn btn-square btn-ghost btn-sm lg:hidden",
                aria_label: "Open menu") { render DocsUI::Icon.new("menu", class: "size-5") }
          a(href: config.brand_href, class: topbar_brand_classes) { brand_mark }
          app_home_link
        end
        render DocsUI::SearchBox.new if config.search_enabled?
        div(class: "flex-none items-center") do
          # The docs-version switcher (config.versions) renders first; nothing
          # unless versioning is enabled, so an unversioned topbar is unchanged.
          render DocsUI::VersionSwitcher.new
          # Config-driven repo/social links (config.topbar_links) render as
          # icon-only ghost buttons BEFORE the switcher; nothing when unset.
          render DocsUI::TopbarLinks.new
          render DocsUI::ThemeSwitcher.new
        end
      end
    end

    # The brand anchor's classes. config.topbar_brand = :mobile_only adds
    # lg:hidden — at the drawer-pinned breakpoint the sidebar brand is already
    # visible, so a site can drop the duplicate. The default (:always) keeps
    # the pre-knob classes verbatim.
    def topbar_brand_classes
      base = "btn btn-ghost text-lg font-bold"
      config.topbar_brand == :mobile_only ? "#{base} lg:hidden" : base
    end

    # The brand: the configured mark (config.brand_logo) when set, else the
    # text brand — byte-identical to before for a site that sets nothing. The
    # text brand stays the mark's accessible-name fallback.
    def brand_mark
      if (logo = config.brand_logo)
        render DocsUI::Logo.new(logo, class: "h-6 w-auto", label: config.brand)
      else
        plain config.brand
      end
    end

    # The opt-in App Home link (config.app_link) — the way back to the hosting
    # app, rendered once, right after the brand. Nothing renders when unset, so
    # the topbar stays byte-identical for a site that never configures it.
    # External hrefs open in a new tab with rel=noopener (same posture as
    # DocsUI::TopbarLinks); a site-relative href opens in place.
    def app_home_link
      link = config.app_link
      return unless link

      a(
        href: link.href,
        class: "link link-hover text-sm opacity-70",
        target: (link.external? ? "_blank" : nil),
        rel: (link.external? ? "noopener noreferrer" : nil)
      ) { link.label }
    end
  end
end
