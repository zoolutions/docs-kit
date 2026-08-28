# frozen_string_literal: true

require "rouge"

module DocsUI
  # A syntax-highlighted code block for docs and demo panels. Rouge does the
  # highlighting; an optional filename/label sits in a title bar like a real docs
  # code sample. Self-contained: it injects its own Rouge theme CSS so no separate
  # stylesheet asset is required.
  #
  #   render DocsUI::Code.new(ruby_source)                          # ruby, no title
  #   render DocsUI::Code.new(yaml, filename: "config/deploy.yml")  # yaml, inferred
  #   render DocsUI::Code.new(py, lexer: :python, filename: "a.py")  # explicit wins
  #
  # The language resolves in order: an explicit `lexer:`; a guess from the
  # `filename:` (Rouge's own filename globs — *.yml → yaml, Dockerfile → docker,
  # *.sh → shell, …); else ruby. Any language Rouge knows (~200 lexers) works by
  # its name or alias — python, go, rust, elixir, kotlin, swift, json,
  # dockerfile, ... — no allowlist. Add friendly lexer aliases via
  # DocsKit.configure (code_lexer_aliases). An unknown language falls back to
  # plaintext (never raises). (Tab labels are a
  # DocsUI::Example concern — set via code_language_labels, not here; Code has no
  # label, only a filename.)
  class Code < Phlex::HTML
    include Phlex::Rails::Helpers::ContentSecurityPolicyNonce

    FORMATTER = Rouge::Formatters::HTML.new

    def initialize(source, lexer: nil, filename: nil)
      @source = source.to_s.strip
      @lexer = lexer
      @filename = filename
    end

    def view_template
      # Nonce the inline theme CSS so it survives a nonce-based style-src. Off a
      # request there is no nonce (see #csp_nonce) and Phlex omits a nil-valued
      # attribute, so the no-nonce markup is unchanged.
      style(nonce: csp_nonce) { highlight_css }
      resolved = lexer
      div(class: "not-prose my-4 overflow-hidden rounded-box border border-base-300 bg-base-300/40") do
        title_bar if @filename
        # data-md-lang carries the RESOLVED Rouge tag (ruby/python/plaintext/…) so
        # DocsKit::MarkdownExport emits a ```lang fence without re-resolving the
        # language. It's the real lexer tag, not the requested alias.
        div(class: "code-highlight overflow-x-auto p-4 text-sm leading-relaxed", data: { md_lang: resolved.tag }) do
          pre { raw(safe(FORMATTER.format(resolved.lex(@source)))) }
        end
      end
    end

    private

    # The request's CSP nonce, or nil when there's no Rails view context (an
    # isolated Phlex render, or a host that doesn't nonce style-src). The
    # phlex-rails value helper delegates to view_context, which raises without
    # one, so guard on its presence — a nil result makes Phlex omit the
    # attribute, keeping the un-nonced markup unchanged.
    def csp_nonce = view_context && content_security_policy_nonce

    def title_bar
      # data-md-skip: the title bar is chrome. MarkdownExport strips it whole
      # before the visitor runs, so the filename never leaks into the .md twin as
      # a stray line above the fence. The visible HTML is unaffected (DROP_SELECTOR
      # is applied only inside #to_md).
      div(class: "flex items-center gap-2 border-b border-base-300 bg-base-300/60 px-4 py-2",
          data: { md_skip: true }) do
        render DocsUI::Icon.new("file-code", class: "size-3.5 opacity-60")
        span(class: "font-mono text-xs opacity-70") { @filename }
      end
    end

    # Resolve the lexer to a Rouge lexer instance. Order: an explicit Rouge::Lexer
    # class/instance passed through; an explicit name via a configured friendly
    # alias → Rouge's own registry → the configured fallback (plaintext); with no
    # `lexer:` given, a guess from the filename; else the ruby default.
    def lexer
      explicit_lexer ||
        (@lexer && (find_lexer(@lexer.to_s) || Rouge::Lexers::PlainText).new) ||
        guessed_lexer ||
        Rouge::Lexers::Ruby.new
    end

    # A lexer inferred from @filename via Rouge's declared filename globs, or nil
    # when there is no filename, nothing matches, or the match is ambiguous.
    # (Lexer.guesses, not Lexer.guess: the latter answers PlainText for a
    # no-match, which is indistinguishable from a real guess.)
    def guessed_lexer
      return nil if @filename.nil?

      guesses = Rouge::Lexer.guesses(filename: @filename.to_s)
      guesses.size == 1 ? guesses.first.new : nil
    end

    # A Rouge::Lexer instance passed directly (class or instance), else nil.
    def explicit_lexer
      return @lexer if @lexer.is_a?(Rouge::Lexer)
      return @lexer.new if @lexer.is_a?(Class) && @lexer < Rouge::Lexer

      nil
    end

    # Find a lexer CLASS by name: configured alias → Rouge registry → fallback.
    def find_lexer(name)
      config = DocsKit.configuration
      aliased = config.lexer_aliases[name.to_sym]
      (aliased && Rouge::Lexer.find(aliased.to_s)) ||
        Rouge::Lexer.find(name) ||
        Rouge::Lexer.find(config.code_lexer_fallback.to_s)
    end

    # Static Rouge theme CSS — no user input. Phlex safe(), not html_safe.
    #
    # The base (light) theme is emitted un-scoped so it applies to every theme.
    # When a dark theme is configured (config.code_theme_dark), its CSS is
    # additionally emitted scoped under [data-theme=X] .code-highlight for each
    # shipped dark theme, so daisyUI's more-specific [data-theme] selector wins
    # and code blocks restyle with the switcher — CSS-only, no JS, no flash.
    # With no dark theme configured this reduces to the original single-theme
    # output byte-for-byte (backwards compatible).
    def highlight_css
      theme = DocsKit.configuration.code_theme_class
      raw(safe(<<~CSS))
        #{theme.render(scope: '.code-highlight')}#{dark_highlight_css}
        .code-highlight pre { margin: 0; white-space: pre-wrap; word-break: break-word; }
      CSS
    end

    # The dark theme's CSS, one block per shipped dark theme, each scoped under
    # [data-theme=X] .code-highlight. Empty string when no dark theme is
    # configured (or no shipped theme is dark) so #highlight_css is unchanged.
    def dark_highlight_css
      config = DocsKit.configuration
      dark = config.code_theme_dark_class
      return "" if dark.nil?

      config.dark_themes_shipped.map do |name|
        "\n#{dark.render(scope: "[data-theme=#{name}] .code-highlight")}"
      end.join
    end
  end
end
