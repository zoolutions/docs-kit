# frozen_string_literal: true

module DocsUI
  # A callout box (note / tip / warning) for the docs. daisyUI alert styling + a
  # lucide icon per level.
  #
  #   render DocsUI::Callout.new(:warning) { "Restart the server after…" }
  class Callout < Phlex::HTML
    LEVELS = {
      note: { klass: "alert-info", icon: "info" }.freeze,
      tip: { klass: "alert-success", icon: "lightbulb" }.freeze,
      warning: { klass: "alert-warning", icon: "triangle-alert" }.freeze
    }.freeze

    def initialize(level = :note, title: nil)
      # Normalize an unknown level to :note so both the styling and the
      # data-md-callout export hint agree (never a bogus level name leaking out).
      @level = LEVELS.key?(level) ? level : :note
      @config = LEVELS[@level]
      @title = title
    end

    def view_template(&)
      # data-md-callout carries the level (note/tip/warning) so
      # DocsKit::MarkdownExport renders `> **Tip:** …` without reverse-engineering
      # the level from the alert-* class.
      div(class: "not-prose alert #{@config[:klass]} my-4 items-start", role: "note",
          data: { md_callout: @level }) do
        render DocsUI::Icon.new(@config[:icon], class: "size-5 shrink-0")
        div do
          div(class: "font-semibold") { @title } if @title
          div(class: "text-sm", &)
        end
      end
    end
  end
end
