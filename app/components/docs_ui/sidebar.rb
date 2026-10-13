# frozen_string_literal: true

module DocsUI
  # The drawer sidebar: a brand header (with an optional version badge) over the
  # nav, driven entirely by DocsKit.configuration.nav_groups. Renders inside the
  # daisyUI drawer-side (DocsUI::Shell owns responsive visibility), so this is just
  # the panel content.
  #
  # nav_groups is an ordered Hash:
  #   { "Heading" => { "Subgroup" => [DocsKit::NavItem, ...] } }
  #
  # Subgroups are the top level of the rendered menu. A lone heading (the common
  # single-registry site) is not rendered at all — the brand masthead already
  # labels the sidebar; with several headings, each renders as a STATIC
  # `.menu-title` label (no fold) and only subgroups collapse.
  class Sidebar < Phlex::HTML
    include Phlex::Rails::Helpers::Request
    include DaisyUI

    # Suppress the browser's native <details> disclosure triangle on nav summaries.
    # daisyUI draws its OWN rotating chevron (li>details>summary::after), so the
    # native marker would render a SECOND, non-rotating caret stacked next to it.
    # daisyUI only hides the old ::-webkit-details-marker; modern browsers (and
    # Safari) also need list-none + the standard ::marker reset. Literal classes —
    # Tailwind tree-shakes interpolated ones.
    MARKER_RESET = "list-none [&::-webkit-details-marker]:hidden [&::marker]:content-none"

    def view_template
      # The docs-nav Stimulus controller lives on <body> (DocsUI::Shell) so it spans
      # this sidebar AND the content column. Here it drives collapse persistence
      # and, in :sidebar mode, hosts the injected page TOC. With JS off the server
      # renders every <details open>, so the sidebar is simply fully expanded.
      div(class: "bg-base-200 flex min-h-full w-72 flex-col") do
        header_section
        div(class: "flex-1 overflow-y-auto px-2 pb-6") do
          Menu(class: "w-full gap-1") do
            groups = nav_groups.reject { |_, grouped| grouped.nil? || grouped.empty? }
            groups.each { |heading, grouped| nav_group(heading, grouped, labeled: groups.size > 1) }
          end
        end
      end
    end

    private

    def config = DocsKit.configuration
    def nav_groups = config.nav_groups

    def header_section
      div(class: "flex min-h-16 items-center gap-2 px-4") do
        a(href: config.brand_href, class: "text-lg font-bold text-base-content") { brand_mark }
        badge = config.version_badge_text
        span(class: "badge badge-sm badge-ghost") { badge } if badge
      end
    end

    # The brand: the configured mark (config.brand_logo) when set, else the
    # text brand — byte-identical to before for a site that sets nothing.
    # Slightly taller than the topbar's h-6: this is the masthead.
    def brand_mark
      if (logo = config.brand_logo)
        render DocsUI::Logo.new(logo, class: "h-7 w-auto", label: config.brand_text)
      else
        plain config.brand_text
      end
    end

    # A top-level group (e.g. "Docs") holding collapsible sub-groups (e.g.
    # "Guide", "Examples"). `grouped` is a { subgroup => [items] } Hash. The
    # heading label only renders when the sidebar shows SEVERAL groups
    # (labeled:) — as a static `.menu-title`, never a <details>, so subgroups
    # stay at the menu's top level instead of gaining a nesting indent. The
    # mt-4/first:mt-0 pair is the breathing room between one group's links and
    # the next group's label.
    def nav_group(heading, grouped, labeled:)
      if labeled
        li(class: "menu-title mt-4 text-xs font-semibold uppercase tracking-wider text-base-content/50 first:mt-0") do
          heading
        end
      end
      grouped.each { |subgroup, items| nav_subgroup(subgroup, items) }
    end

    # A collapsible sub-group: its title is a <summary> so the whole section folds
    # away. daisyUI's Menu renders nested li>details as an accordion natively.
    #
    # NOTE: a collapsible summary must NOT carry `.menu-title` — daisyUI reserves
    # that for a STATIC (non-<details>) heading and its layout rule for the
    # rotating caret is `summary:not(.menu-title)`. A `.menu-title` summary loses
    # the grid layout, so its chevron drops below-left of the label instead of
    # right-aligning like the top-level group's. Style it as a plain summary
    # (matching daisyUI's own collapsible-submenu example) so both carets align.
    def nav_subgroup(subgroup, items)
      li do
        details(open: true) do
          summary(class: "text-xs font-medium text-base-content/60 #{MARKER_RESET}") { subgroup }
          ul do
            items.each { |item| li { nav_link(item) } }
          end
        end
      end
    end

    def nav_link(item)
      a(href: item.href, class: link_classes(item.href)) do
        render DocsUI::Icon.new(item.icon, class: "size-4 shrink-0") if item.icon
        span(class: "truncate") { item.label }
      end
    end

    def link_classes(href)
      active = current_path == href
      ["flex items-center gap-3", (active ? "menu-active font-medium" : nil)].compact
    end

    def current_path
      request&.path
    rescue StandardError
      nil
    end
  end
end
