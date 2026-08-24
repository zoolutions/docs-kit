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
  # NOTE (issue #61 phase 4): the "you are viewing the 1.0 docs" banner with a
  # link to the current equivalent lands with the version switcher, not here.
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

    # The masthead + Markdown body — separated from the Shell wrapper so it can
    # render (and be specced) without a Rails view context, the same seam as
    # Shell's own topbar/theme-script specs.
    def body
      render DocsUI::Header.new(@entry.title) if @entry&.title
      render DocsUI::Markdown.new(markdown_source) unless markdown_source.empty?
    end

    private

    def markdown_source
      @markdown_source ||= @entry ? @entry.markdown.to_s : ""
    end
  end
end
