# frozen_string_literal: true

module DocsKit
  # The ONE request-scoped content scope: which documentation version (and,
  # come i18n M2, which locale) the current render serves. Controllers set it
  # around an action (DocsKit::Controller#render_page, DocsKit::Scoping); the
  # config and the components consult it (Configuration#nav_groups,
  # LlmsText.pages) — so "which content tree?" is asked once per request, not
  # threaded through every component.
  #
  #   DocsKit::Scope.with(version: v) { ... }   # block-scoped, restores in an ensure
  #   DocsKit::Scope.version                    # the DocVersion in scope, or nil
  #   DocsKit::Scope.locale                     # reserved for i18n M2 — nil today
  #   DocsKit::Scope.path_prefix                # "" or "/1.0"
  #
  # Backed by Thread.current[] — fiber-local in Ruby, which is what a fibered
  # server wants — and deliberately Rails-free (NOT CurrentAttributes), so bare
  # Phlex component specs can set a scope without booting Rails. An empty scope
  # (no `with` in flight) reads as nil version / nil locale, which every
  # consumer treats as "the current version" — today's behavior exactly.
  module Scope
    KEY = :docs_kit_scope

    EMPTY = { version: nil, locale: nil }.freeze
    private_constant :EMPTY

    module_function

    # Run the block with this version/locale in scope, restoring the previous
    # scope on the way out — even when the block raises — so nothing leaks
    # across requests sharing a thread.
    def with(version: nil, locale: nil)
      previous = Thread.current[KEY]
      Thread.current[KEY] = { version: version, locale: locale }
      yield
    ensure
      Thread.current[KEY] = previous
    end

    # The DocsKit::DocVersion in scope, or nil (treated as the current version).
    def version
      current[:version]
    end

    # Reserved for i18n M2 — always nil until the locale axis is wired.
    def locale
      current[:locale]
    end

    # The root URL prefix the in-scope version contributes ("" when none/current).
    def path_prefix
      version&.path_prefix || ""
    end

    def current
      Thread.current[KEY] || EMPTY
    end
  end
end
