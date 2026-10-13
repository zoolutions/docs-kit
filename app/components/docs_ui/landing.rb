# frozen_string_literal: true

module DocsUI
  # The marketing landing page — a hero (an optional brand logo + eyebrow + title +
  # lead + optional install snippet + CTA buttons), a feature-card grid, and a
  # registry-grouped documentation index — rendered inside DocsUI::Shell. Every
  # consuming site was hand-rolling this; drive it from config instead:
  #
  #   # config/initializers/docs_kit.rb
  #   DocsKit.configure do |c|
  #     c.landing.logo     = { svg: "M4 2h9l5 5…Z", viewbox: "0 0 22 24", label: "Acme" }
  #     c.landing.eyebrow  = "Developer Docs"
  #     c.landing.title    = "Jobs & events on **Postgres**"   # ** ** → primary color
  #     c.landing.lead     = "PostgreSQL-native jobs + event bus for Rails."
  #     c.landing.install  = { code: 'gem "pgbus"', filename: "Gemfile", lexer: :ruby }
  #     c.landing.ctas     = [{ label: "Get started", href: "/docs/overview", style: :primary }]
  #     c.landing.features = [{ icon: "database", title: "One database", body: "No Redis." }]
  #   end
  #
  #   # a controller that includes DocsKit::Controller
  #   def show = render_page(DocsUI::Landing.new)
  #
  # Everything is optional: with an empty c.landing it still renders a minimal hero
  # (the brand name + the doc index), never a broken page. The doc index is built
  # from DocsKit.configuration.nav_groups — the same registry the sidebar uses — so
  # it never drifts from the authored pages.
  #
  # It IS a full document (composes Shell), so a controller renders it with
  # `layout: false`, exactly like DocsUI::Page (DocsKit::Controller#render_page
  # does this). The `.md`/`.text` twin of the landing works too — MarkdownExport
  # walks the same #docs-content region Shell stamps.
  class Landing < Phlex::HTML
    include Phlex::Rails::Helpers::Request

    def view_template
      render DocsUI::Shell.new(title: landing.eyebrow || config.brand_text) do
        div(class: "mx-auto max-w-5xl") do
          hero
          feature_grid
          doc_index
        end
      end
    end

    private

    def config = DocsKit.configuration
    def landing = config.landing

    # --- hero ----------------------------------------------------------------

    def hero
      div(class: "flex flex-col gap-6") do
        logo
        eyebrow
        heading
        lead
        install_snippet
        ctas
      end
    end

    # The brand mark — the shared DocsUI::Logo renderer (any DocsKit::BrandLogo
    # form) at hero size. Rendered above the eyebrow, like a product wordmark.
    def logo
      return unless (mark = landing.hero_logo)

      render DocsUI::Logo.new(mark, class: "h-9 w-auto text-primary")
    end

    def eyebrow
      return unless (text = landing.eyebrow)

      p(class: "text-sm font-medium uppercase tracking-wide text-primary") { text }
    end

    # The <h1>. A **run** wrapped in double asterisks renders in the primary color
    # (the one bit of markdown we honor, so a site can accent a word without HTML).
    def heading
      h1(class: "text-4xl font-bold tracking-tight md:text-5xl") do
        (landing.title || config.brand_text).to_s.split(/\*\*(.+?)\*\*/).each_with_index do |part, index|
          next if part.empty?

          index.odd? ? span(class: "text-primary") { part } : plain(part)
        end
      end
    end

    def lead
      return unless (text = landing.lead || config.tagline)

      p(class: "max-w-2xl text-lg text-base-content/70") { text }
    end

    def install_snippet
      return unless (snippet = landing.install_snippet)

      render DocsUI::Code.new(snippet[:code], lexer: snippet[:lexer], filename: snippet[:filename])
    end

    def ctas
      buttons = landing.ctas
      return if buttons.empty?

      div(class: "flex flex-wrap items-center gap-4 pt-2") do
        buttons.each { |cta| cta_button(cta) }
      end
    end

    def cta_button(cta)
      attrs = { href: cta.href, class: "#{cta.btn_class} gap-2" }
      if cta.external?
        attrs[:target] = "_blank"
        attrs[:rel] = "noopener"
      end
      a(**attrs) do
        render DocsUI::BrandMark.new(cta.icon, class: "size-4", label: cta.label) if cta.icon
        plain cta.label
      end
    end

    # --- feature grid --------------------------------------------------------

    def feature_grid
      features = landing.features
      return if features.empty?

      div(class: "mt-12 grid gap-4 sm:grid-cols-2") do
        features.each { |feature| feature_card(feature) }
      end
    end

    def feature_card(feature)
      div(class: "rounded-box border border-base-300 bg-base-200/40 p-5") do
        div(class: "flex items-center gap-2 text-primary") do
          render DocsUI::Icon.new(feature.icon, class: "size-5") if feature.icon
          span(class: "font-semibold text-base-content") { feature.title }
        end
        p(class: "mt-2 text-sm text-base-content/70") { feature.body } if feature.body
      end
    end

    # --- documentation index -------------------------------------------------

    # The registry-grouped page index. nav_groups is the three-level Hash the
    # sidebar renders ({ heading => { subgroup => [NavItem] } }); the landing
    # flattens each heading's items into a linked column.
    def doc_index
      return if !landing.doc_index? || (groups = flattened_nav).empty?

      div(class: "mt-16") do
        h2(class: "text-sm font-semibold uppercase tracking-wide text-base-content/50") { "Documentation" }
        div(class: "mt-6 grid gap-8 sm:grid-cols-2") do
          # A lone heading would just repeat the h2 above (often literally
          # "Documentation"), so only label the columns when there are several.
          groups.each { |heading, items| doc_index_group(heading, items, labeled: groups.size > 1) }
        end
      end
    end

    def doc_index_group(heading, items, labeled:)
      div do
        h3(class: "text-xs font-semibold uppercase tracking-wide text-base-content/40") { heading } if labeled
        ul(class: labeled ? "mt-3 flex flex-col gap-2" : "flex flex-col gap-2") do
          items.each { |item| li { a(href: item.href, class: "link link-hover text-sm") { item.label } } }
        end
      end
    end

    # Collapse nav_groups ({ heading => { subgroup => [item] } }) to
    # { heading => [item, ...] } — the landing shows one flat column per heading.
    def flattened_nav
      config.nav_groups.each_with_object({}) do |(heading, grouped), acc|
        items = Array(grouped).flat_map { |_subgroup, list| Array(list) }
        acc[heading] = items unless items.empty?
      end
    end
  end
end
