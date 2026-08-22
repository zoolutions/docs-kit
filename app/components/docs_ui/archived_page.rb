# frozen_string_literal: true

module DocsUI
  # Renders one page of an ARCHIVED documentation version — a frozen Markdown
  # body (DocsKit::Snapshot::Entry) through today's live chrome, so archived
  # docs get every future Shell/Sidebar/Code fix for free. The live counterpart
  # is DocsUI::Page; this mirrors its shape with the content coming from the
  # snapshot file instead of an authored #content method.
  #
  # Every kwarg defaults, so even a naive `entry.view_class.new` (a custom
  # registry predating #renderable) renders an empty page rather than raising.
  #
  # Deliberately does NOT include Phlex::Rails::Helpers::Routes/Request — their
  # bodies run Rails.* at class load, which would make this class (and
  # everything referencing it, like Snapshot::Entry#view_class) unloadable in a
  # Rails-free render. Nothing here needs a request.
  class ArchivedPage < Phlex::HTML
    include DocsUI

    def initialize(entry: nil)
      @entry = entry
    end

    def view_template
      render DocsUI::Shell.new(title: @entry&.title) { body }
    end

    # The banner + masthead + Markdown body — separated from the Shell wrapper
    # so it can render (and be specced) without a Rails view context, the same
    # seam as Shell's own topbar/theme-script specs.
    def body
      banner
      render DocsUI::Header.new(@entry.title) if @entry&.title
      render DocsUI::Markdown.new(markdown_source) unless markdown_source.empty?
    end

    private

    # The "you are viewing archived docs" banner, linking the same slug in the
    # current version (falling back to the docs home when the page no longer
    # exists there). data-md-skip drops it from the Markdown twin — it's chrome,
    # not page content. Absent for a current-version entry (a snapshot of the
    # current release rendered directly) and for entries carrying no version.
    def banner
      version = entry_version
      return unless version&.archived?

      current = DocsKit.configuration.current_version
      div(data: { md_skip: true }) do
        render DocsUI::Callout.new(:warning) do
          plain "You are viewing the #{version.label} docs."
          if current
            plain " The current version is #{current.label} — "
            a(href: current_equivalent_href, class: "link") { "read it there" }
            plain "."
          end
        end
      end
    end

    def entry_version
      @entry.version if @entry.respond_to?(:version)
    end

    # The current-version page with this entry's slug, or the docs home when
    # the slug has no current equivalent (a page removed since this version).
    def current_equivalent_href
      config = DocsKit.configuration
      slug = @entry.respond_to?(:slug) ? @entry.slug : nil
      live = slug && DocsKit::LlmsText.pages(config, version: config.current_version)
                                      .find { |page| page.slug.to_s == slug.to_s }
      live&.href || config.brand_href
    end

    def markdown_source
      @markdown_source ||= @entry ? @entry.markdown.to_s : ""
    end
  end
end
