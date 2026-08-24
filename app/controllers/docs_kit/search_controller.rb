# frozen_string_literal: true

module DocsKit
  # Serves the docs search — one gem controller, host-drawn route (same shape as
  # DocsKit::LlmsController; the engine is glue-only and adds no routes):
  #
  #   # config/routes.rb
  #   get "/docs/search" => "docs_kit/search#index"
  #
  # #index answers BOTH formats off the same index:
  #
  #   * html — the JS-off path: renders DocsUI::SearchResults inside DocsUI::Shell,
  #     a full working results page. The topbar form (GET ?q=) lands here.
  #   * json — the enhancement path: the docs-nav palette fetches `search.json?q=`
  #     debounced and renders the hits client-side. The form still submits to the
  #     html path if JS dies mid-typing.
  #
  # The index is built lazily per request from DocsKit::SearchIndex, whose entries
  # come from each registry page's Markdown twin (DocsKit::MarkdownExport) split on
  # its `## ` headings — the SAME twins llms-full.txt serves, so search can never
  # drift from the pages. Sites are tens of pages; there's no external index, no
  # build step, no second registry.
  class SearchController < ActionController::Base
    # Like LlmsController: a bare ActionController::Base subclass doesn't inherit
    # the host's default_protect_from_forgery, and #index renders DocsUI::Shell,
    # whose <head> calls csrf_meta_tags (which needs protect_against_forgery?
    # registered as a view helper). :null_session fits this GET-only, sessionless,
    # public endpoint.
    protect_from_forgery with: :null_session

    # Search follows the request's version: /1.0/docs/search searches the 1.0
    # snapshot, /docs/search searches current — the scope swaps the enumeration
    # source underneath DocsKit::LlmsText.pages.
    include DocsKit::Scoping

    def index
      hits = search_index.search(query)

      respond_to do |format|
        format.html { render_results_page(hits) }
        format.json { render json: { "query" => query, "results" => hits.map(&:as_json) } }
      end
    end

    private

    # NOT named #config — ActionController::Base#config is the Rails config object
    # and RequestForgeryProtection delegates to it; shadowing it breaks
    # csrf_meta_tags when the Shell renders (see LlmsController).
    def docs_config = DocsKit.configuration

    def query = params[:q].to_s

    # The index built from every authored registry page's Markdown twin. Each page
    # is rendered through THIS controller's view context (url helpers/CSRF resolve)
    # and absolutized against the request base URL, exactly as LlmsController#full
    # renders each twin.
    def search_index
      triples = DocsKit::LlmsText.pages(docs_config).map do |page|
        markdown = DocsKit::MarkdownExport.new(
          DocsKit::LlmsText.renderable_for(page), view_context:, base_url: request.base_url
        ).to_md
        [page.title, page.href, markdown]
      end
      DocsKit::SearchIndex.new(triples)
    end

    # The full chrome results page. DocsUI::Shell IS the whole document, so render
    # with layout: false (the same contract as DocsKit::Controller#render_page).
    def render_results_page(hits)
      page = DocsUI::Shell.new(title: "Search") do
        render DocsUI::SearchResults.new(query:, hits:)
      end
      render page, layout: false
    end
  end
end
