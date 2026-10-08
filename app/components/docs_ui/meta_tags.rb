# frozen_string_literal: true

module DocsUI
  # The SEO / social-share <head> tags: description, Open Graph, Twitter Card,
  # canonical, favicon, robots, theme-color. Rendered by DocsUI::Shell inside
  # <head>, driven entirely by DocsKit.configuration (+ .seo) and the per-page
  # title/description — so every docs site is share-ready with zero markup, and a
  # site tunes it through config alone (no Shell subclass).
  #
  #   render DocsUI::MetaTags.new(title: "Installation", description: "…")
  #
  # All free text (title, description, brand) is emitted as normal Phlex
  # attribute values, so Phlex escapes it — config free text is never trusted
  # markup. The og:image is SITE content (nil by default → no og:image tag): a
  # relative og_image is resolved through the SITE'S asset pipeline (image_url) to
  # the DIGESTED /assets URL Propshaft serves — NOT the raw config path, which
  # 404s; an absolute URL passes through. canonical/og:url come from
  # config.seo.site_url, else the request URL; both are omitted off a request
  # (guarded like Shell#csp_nonce, so an isolated render never raises).
  class MetaTags < Phlex::HTML
    include Phlex::Rails::Helpers::Request
    include Phlex::Rails::Helpers::ImageURL

    # title:       the page title (nil on a page that sets none, e.g. the home
    #              page) — combined with config.title_suffix for og:title.
    # description: the page's resolved description (DocsUI::Page passes its own
    #              description or #lead); nil falls back to config.seo.description.
    def initialize(title: nil, description: nil)
      @title = title
      @description = description
    end

    def view_template
      description_meta
      open_graph
      twitter_card
      canonical_link
      favicon_link
      robots_meta
      theme_color_meta
    end

    private

    def config = DocsKit.configuration
    def seo = config.seo

    # The page description, falling back to the site-wide default. nil → the
    # description tags (meta description, og:description) are omitted.
    def description = @description || seo.description

    # The full title used for og:title, identical to what Shell puts in <title>:
    # "Page · Suffix", or just the suffix on a title-less page (the home page).
    def full_title
      [@title, config.title_suffix].compact.join(" · ")
    end

    def description_meta
      return unless description

      meta(name: "description", content: description)
    end

    # The always-present minimal OG block (title/type/site_name) plus the opt-in
    # description/image/url. A site that configures nothing still gets a valid
    # card — never a broken empty tag.
    def open_graph
      meta(property: "og:title", content: full_title)
      meta(property: "og:type", content: seo.og_type)
      meta(property: "og:site_name", content: config.brand)
      open_graph_optional
    end

    # The OG tags emitted only when their value resolves — kept separate so the
    # always-present block above stays a flat, obvious minimum.
    def open_graph_optional
      meta(property: "og:locale", content: seo.locale) if seo.locale
      meta(property: "og:description", content: description) if description
      meta(property: "og:image", content: og_image_url) if og_image_url
      meta(property: "og:url", content: canonical_url) if canonical_url
    end

    def twitter_card
      meta(name: "twitter:card", content: seo.twitter_card)
      meta(name: "twitter:site", content: seo.twitter_site) if seo.twitter_site
      meta(name: "twitter:creator", content: seo.twitter_creator) if seo.twitter_creator
      meta(name: "twitter:image", content: og_image_url) if og_image_url
    end

    def canonical_link
      return unless canonical_url

      link(rel: "canonical", href: canonical_url)
    end

    def favicon_link
      return unless seo.favicon

      link(rel: "icon", href: seo.favicon)
    end

    # An archived version in scope is noindex'd ("noindex, follow" — search
    # engines keep pointing at the current docs while still crawling through)
    # unless the version opts out with noindex: false; the canonical stays
    # self-referential (pointing it at different content would send a second,
    # conflicting signal). Otherwise: today's opt-in seo.robots exactly.
    def robots_meta
      return meta(name: "robots", content: "noindex, follow") if scope_noindex?
      return unless seo.robots

      meta(name: "robots", content: seo.robots)
    end

    def scope_noindex?
      !!DocsKit::Scope.version&.noindex
    end

    def theme_color_meta
      return unless seo.theme_color

      meta(name: "theme-color", content: seo.theme_color)
    end

    # The og:image as an absolute URL a crawler can fetch, or nil to emit NO
    # og:image (a valid card without an image — never a 404). nil when og_image is
    # unset (the default). An already-absolute og_image passes through. A relative
    # path is a logical asset in the SITE'S pipeline, resolved through image_url to
    # the DIGESTED, host-qualified /assets URL Propshaft actually serves
    # (https://host/assets/og/og-<digest>.png) — never the raw config path, which
    # 404s. Off a request (an isolated render / static build) there is no asset
    # pipeline to resolve a relative path, so we emit nothing rather than a
    # guessed-and-wrong URL; a real app always renders with a view context.
    def og_image_url
      image = seo.og_image
      return if image.to_s.empty?
      return image if absolute?(image)

      resolve_asset(image)
    end

    # Resolve a logical asset path to its served (digested, host-qualified) URL via
    # the Rails asset helper. nil when there's no view context (image_url delegates
    # to view_context, which raises without one — the same seam Shell#csp_nonce
    # guards), so an isolated render emits no og:image rather than raising.
    #
    # A configured-but-unresolvable og_image (asset missing / not precompiled)
    # raises the pipeline's MissingAssetError — intended, NOT rescued: a broken
    # og_image is a real misconfiguration that must surface at deploy time
    # (assets:precompile runs before the app serves), not ship silently-broken
    # social cards. A site with no card image leaves og_image nil (see #og_image_url).
    def resolve_asset(path)
      return unless view_context

      image_url(path)
    end

    # The canonical/og:url for this page. From config.seo.site_url when set (its
    # path is honored verbatim so a site can point canonical at a specific URL),
    # else the request's original URL. nil when neither is available (an isolated
    # render), so canonical/og:url are simply omitted.
    def canonical_url
      return seo.site_url if seo.site_url
      return unless request?

      request.original_url
    end

    def absolute?(url) = url.to_s.match?(%r{\Ahttps?://}i)

    # True only when there's a live Rails view context AND a request on it — the
    # phlex-rails #request helper delegates to view_context, which raises without
    # one. Mirrors Shell#csp_nonce's guard so an isolated Phlex render (the specs,
    # a request-less static build) degrades cleanly instead of raising.
    def request? = !view_context.nil? && !request.nil?
  end
end
