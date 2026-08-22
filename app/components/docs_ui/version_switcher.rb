# frozen_string_literal: true

module DocsUI
  # The topbar documentation-version switcher — the DocsUI::ThemeSwitcher
  # dropdown pattern (tabindex/role=button + dropdown-content): daisyUI's
  # dropdown opens on CSS :focus-within, so it works with JavaScript off, and
  # every entry is a plain <a> — no Stimulus controller (the ONE-controller
  # rule).
  #
  # Renders NOTHING unless config.versioning_enabled? (two or more configured
  # versions), so an unversioned site's topbar is byte-identical to before.
  #
  # Each link targets the SAME slug in the target version when that page exists
  # there, falling back to the target version's first page — a slug missing
  # from an older snapshot must never link a 404.
  class VersionSwitcher < Phlex::HTML
    include Phlex::Rails::Helpers::Request

    def view_template
      return unless config.versioning_enabled?

      div(class: "dropdown dropdown-end", data: { testid: "version-switcher" }) do
        div(tabindex: "0", role: "button", class: "btn btn-sm btn-ghost gap-1") do
          render DocsUI::Icon.new("layers", class: "size-4")
          plain scope_version.label
        end
        ul(tabindex: "0",
           class: "dropdown-content bg-base-300 rounded-box z-10 w-44 p-2 shadow-2xl") do
          config.versions.each { |version| version_option(version) }
        end
      end
    end

    private

    def config = DocsKit.configuration

    # The version this render serves: the request scope, else the current
    # version (versioning_enabled? guarantees one exists — with none marked
    # current, the first configured entry is it).
    def scope_version
      DocsKit::Scope.version || config.current_version
    end

    def version_option(version)
      in_scope = version.id == scope_version&.id
      li do
        a(
          href: target_href(version),
          class: "btn btn-sm btn-block btn-ghost justify-start",
          aria_current: (in_scope ? "true" : nil)
        ) { version.label }
      end
    end

    # The same slug in the target version when it exists there; else the
    # target's first page (guaranteed routable — never a 404); else the
    # target-prefixed docs root (an empty snapshot is already a degraded state).
    def target_href(version)
      pages = DocsKit::LlmsText.pages(config, version: version)
      candidate = candidate_href(version)
      return candidate if candidate && pages.any? { |page| page.href == candidate }

      pages.first&.href || "#{version.path_prefix}/docs"
    end

    # The current request path re-prefixed for the target version: strip the
    # in-scope version's prefix, add the target's. nil without a request.
    def candidate_href(version)
      path = current_path
      return unless path

      "#{version.path_prefix}#{path.delete_prefix(DocsKit::Scope.path_prefix)}"
    end

    # The request path, nil when rendered without a live request (an isolated
    # render, a static build) — the DocsUI::Sidebar#current_path guard.
    def current_path
      request&.path
    rescue StandardError
      nil
    end
  end
end
