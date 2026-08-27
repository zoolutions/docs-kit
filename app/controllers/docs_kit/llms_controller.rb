# frozen_string_literal: true

module DocsKit
  # Serves the two AI-readable artifacts (llmstxt.org) from the registry, with
  # zero authoring — the host app wires the routes (the engine is glue-only, no
  # routes of its own), so a site keeps full control over path, auth, and
  # omission:
  #
  #   # config/routes.rb
  #   get "/llms.txt"      => "docs_kit/llms#index"
  #   get "/llms-full.txt" => "docs_kit/llms#full"
  #
  # #index → the llms.txt index (brand, tagline, nav-grouped links to each page's
  # `.md` twin). #full → llms-full.txt (every page's Markdown concatenated). Both
  # are text/plain and HTTP-cached: the response revalidates on the registry's
  # own content plus DocsKit::VERSION, so a page/gem change busts the cache while
  # an unchanged registry serves a 304.
  #
  # All the text shaping lives in DocsKit::LlmsText (pure, Rails-free). This
  # controller only threads the Rails view context: #full renders each page to
  # Markdown via DocsKit::MarkdownExport (which needs url helpers/CSRF), then
  # hands the [title, markdown] pairs to LlmsText.full.
  class LlmsController < ActionController::Base
    # #full renders each page's full HTML through this controller's view context
    # (DocsKit::MarkdownExport), and DocsUI::Shell's <head> calls csrf_meta_tags —
    # which needs protect_against_forgery? registered as a view helper. A gem's
    # bare ActionController::Base subclass doesn't inherit the host app's
    # default_protect_from_forgery, so declare it here. :null_session fits these
    # GET-only, sessionless, public text endpoints (no token to verify).
    protect_from_forgery with: :null_session

    # Every action runs in the request's version scope (params[:version] on the
    # version-prefixed routes, else the current version), so the enumeration
    # below serves the version the URL asked for.
    include DocsKit::Scoping

    def index
      body = DocsKit::LlmsText.index(docs_config, base_url: request.base_url)
      render_text(body) if stale_llms?(body)
    end

    def full
      pairs = DocsKit::LlmsText.pages(docs_config).map do |page|
        [page.title, render_page_markdown(page)]
      end
      body = DocsKit::LlmsText.full(docs_config, pairs)
      render_text(body) if stale_llms?(body)
    end

    # Freshness lifetime for a shared cache (dash-proxy, a CDN). `public` on its
    # own is not storable under RFC 9111 — without a max-age the proxy cache
    # skips the response. 300s matches the `proxy.cache.max_ttl` docs-kit
    # scaffolds; the etag below still revalidates within that window.
    LLMS_MAX_AGE = 300

    private

    # NOT named #config — ActionController::Base#config is the Rails config
    # object, and RequestForgeryProtection delegates allow_forgery_protection/
    # csrf_token_storage_strategy to it (`delegate ..., to: :config`). Shadowing
    # #config with DocsKit.configuration would route those to the wrong object and
    # blow up csrf_meta_tags when #full renders a page's <head>.
    def docs_config = DocsKit.configuration

    # text/plain (llms.txt is plain text, not markdown — agent tooling fetches it
    # as-is). UTF-8 because page titles/taglines may carry non-ASCII.
    def render_text(body)
      render plain: body, content_type: "text/plain; charset=utf-8"
    end

    # Revalidate on the rendered body itself (so any registry/config/page change
    # busts it) plus the gem version as the etag salt. In development, always
    # re-render; production sites deploy immutably so the version etag is stable.
    def stale_llms?(body)
      expires_in LLMS_MAX_AGE, public: true
      stale?(etag: [DocsKit::VERSION, body], public: true)
    end

    # A page's Markdown twin, rendered through this controller's view context so
    # url helpers/CSRF resolve and relative links absolutize to portable URLs —
    # the same path DocsKit::Controller#render_page takes for a `.md` request.
    # renderable_for is the live-or-snapshot shim (a snapshot entry renders an
    # ArchivedPage carrying its frozen Markdown).
    def render_page_markdown(page)
      DocsKit::MarkdownExport.new(
        DocsKit::LlmsText.renderable_for(page), view_context:, base_url: request.base_url
      ).to_md
    end
  end
end
