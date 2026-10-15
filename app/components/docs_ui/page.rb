# frozen_string_literal: true

module DocsUI
  # The base class for a hand-authored doc page. Subclasses set the title (and
  # optional eyebrow/lead) and implement #content with the page body, composing
  # the doc kit (Section/Prose/Code/Callout). Page renders it inside DocsUI::Shell
  # with a consistent masthead.
  #
  #   class Views::Docs::Pages::Installation < DocsUI::Page
  #     title "Installation"
  #     eyebrow "Guide"
  #     def lead = "Add the gem and render your first component."
  #     def content
  #       render DocsUI::Section.new("Add the gem") { … }
  #     end
  #   end
  #
  # A page class that renders many records overrides the INSTANCE readers
  # (#title, #description, #eyebrow) instead — they default to the class macros:
  #
  #   class Views::Docs::Widget < DocsUI::Page
  #     eyebrow "Widgets"
  #     def initialize(widget:) = @widget = widget
  #     def title = @widget.name
  #     def content = md(@widget.notes)
  #   end
  class Page < Phlex::HTML
    include Phlex::Rails::Helpers::Routes
    # #request drives the "Markdown" masthead action's href (request.path + .md).
    include Phlex::Rails::Helpers::Request
    # Authored pages subclass this, so include the kit here: a page body can call
    # DocsUI::Section(...) / DocsUI::Code(...) directly, no render ... .new.
    include DocsUI
    # The lowercase, block-friendly authoring helpers (md/prose/example) — the
    # friction-free path that never trips the parens-with-blocks gotcha.
    include DocsUI::PageHelpers

    # The page macros run in a page class's body, at load (boot, on the main
    # Ractor), and make each value shareable on write: request threads only
    # read them afterwards, and a non-main Ractor can too.
    # rubocop:disable-next ThreadSafety/ClassInstanceVariable -- written once in the class body at load; values made shareable
    class << self
      def title(value = nil)
        @title = DocsKit::Shareable.make(value) if value
        @title
      end

      # Inherited: a subclass that sets no eyebrow shows its parent page's.
      def eyebrow(value = nil)
        @eyebrow = DocsKit::Shareable.make(value) if value
        @eyebrow || (superclass.eyebrow if parent_page?)
      end

      # The per-page SEO/social description → DocsUI::MetaTags (via Shell). Set it
      # for a hand-tuned description; when unset, Page derives one from #lead, so
      # an existing page gets a sensible description for free. nil (no
      # description, no lead) falls back to config.seo.description in MetaTags.
      # Inherited from a parent page when unset.
      def description(value = nil)
        @description = DocsKit::Shareable.make(value) if value
        @description || (superclass.description if parent_page?)
      end

      # The "On this page" auto-TOC placement for this page. Defaults to the
      # configured DocsKit.configuration.on_page_default; set false to opt out,
      # or :panel/:toggle/:sidebar to override per page. Inherited from a parent
      # page when unset.
      def on_page(value = :__unset__)
        @on_page = DocsKit::Shareable.make(value) unless value == :__unset__
        return @on_page if defined?(@on_page)

        parent_page? ? superclass.on_page : DocsKit.configuration.on_page_default
      end

      private

      # Whether the superclass is a page too (true below DocsUI::Page itself), so
      # an unset macro falls back to it.
      def parent_page? = superclass <= DocsUI::Page
    end

    def view_template
      render DocsUI::Shell.new(title:, description:, on_page: self.class.on_page) do
        # data-md-skip drops this nav from the Markdown export — it's chrome, not
        # page content (DocsKit::MarkdownExport strips [data-md-skip]). The
        # "Markdown" action sits opposite "← Home"; it's chrome too, so it lives
        # inside the skipped nav and never appears in the .md twin.
        nav(class: "mb-6 flex items-center justify-between gap-4", data: { md_skip: true }) do
          a(href: home_href, class: "link link-hover text-sm opacity-70") { "← Docs home" }
          render DocsUI::MarkdownAction.new(request.path) if markdown_action?
        end

        render DocsUI::Header.new(title, eyebrow:) do
          plain lead if lead
        end

        content
      end
    end

    # Whether to show the "Markdown" masthead action — the config knob
    # (DocsKit.configuration.page_markdown_action, default true). The action links
    # request.path + ".md"; override to false on a page whose route has no .md twin.
    def markdown_action? = DocsKit.configuration.page_markdown_action

    # The page title (masthead <h1> and <title>), eyebrow and SEO description.
    # Each defaults to its class macro; override per instance when one page class
    # renders many records. #title shadows Phlex's <title> element method, on
    # pages only — the document <title> is DocsUI::Shell's, never a page body's.
    def title = self.class.title
    def eyebrow = self.class.eyebrow
    # Falls back to #lead, then (in DocsUI::MetaTags) to config.seo.description.
    def description = self.class.description || lead

    # The lowercase authoring helpers md/prose/example come from DocsUI::PageHelpers
    # (included above) — the parens-free path that never hits the constant-reference
    # SyntaxError. The kit forms (DocsUI::Prose(), DocsUI::Example()) stay valid too.

    # Override in subclasses for the lead paragraph (optional).
    def lead = nil

    # Override in subclasses with the page body.
    def content
      raise NotImplementedError, "#{self.class} must implement #content"
    end

    private

    # The masthead "← Docs home" target: config.brand_href (the DOCS home, like
    # the topbar/sidebar brand links) — never the host's root_path helper, which
    # on an app-embedded site is the application root, not the docs landing.
    def home_href = DocsKit.configuration.brand_href
  end
end
