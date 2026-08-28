# frozen_string_literal: true

RSpec.describe DocsUI::Code do
  it "highlights ruby source and injects scoped theme CSS" do
    html = described_class.new("puts 'hi'").call

    expect(html).to include("code-highlight")
    expect(html).to include("<pre>")
    expect(html).to include(".code-highlight") # the inlined Rouge theme scope
    expect(html).to include("<style>")
  end

  describe "the inline theme <style> under a CSP nonce" do
    context "when there is no CSP nonce (isolated render / host without a nonce)" do
      it "emits a <style> with NO nonce attribute (byte-identical to before)" do
        html = described_class.new("puts 'hi'").call

        expect(html).to include("<style>")
        expect(html).not_to include("nonce")
      end
    end

    context "when a CSP nonce is present (nonce-based style-src)" do
      it "carries the nonce on the inline <style> tag" do
        # In a real request #csp_nonce reads the request's CSP nonce off the view
        # context; here (no request) we override that seam so the nonce path is
        # exercised exactly as production would render it.
        styled = Class.new(described_class) do
          def csp_nonce = "testnonce"
        end
        html = styled.new("puts 'hi'").call

        expect(html).to include('<style nonce="testnonce">')
        expect(html).to include(".code-highlight") # still the Rouge theme CSS
      end
    end
  end

  describe "dark-theme code CSS (code_theme_dark)" do
    it "is byte-identical to the single-theme output when code_theme_dark is nil" do
      # Regression guard: the default (nil) path must not change existing output.
      before = described_class.new("puts 'hi'").call

      DocsKit.configure { |c| c.code_theme_dark = nil }
      after = described_class.new("puts 'hi'").call

      expect(after).to eq(before)
    end

    it "emits dark-theme CSS scoped under [data-theme=X] for each shipped dark theme" do
      DocsKit.configure do |c|
        c.themes = %w[light dark]
        c.code_theme_dark = "Rouge::Themes::Github"
      end
      html = described_class.new("puts 'hi'").call

      expect(html).to include("[data-theme=dark] .code-highlight")
    end

    it "does NOT emit CSS for a dark theme the site doesn't ship" do
      DocsKit.configure do |c|
        c.themes = %w[light dark] # synthwave is dark but NOT shipped
        c.code_theme_dark = "Rouge::Themes::Github"
      end
      html = described_class.new("puts 'hi'").call

      expect(html).not_to include("[data-theme=synthwave]")
    end

    it "still emits the base (light) theme CSS alongside the dark rules" do
      DocsKit.configure do |c|
        c.themes = %w[light dark]
        c.code_theme_dark = "Rouge::Themes::Github"
      end
      html = described_class.new("puts 'hi'").call

      # The un-scoped base rule (light) and the data-theme-scoped dark rule
      # coexist, so the switcher restyles code blocks per theme with no JS.
      expect(html).to include(".code-highlight")
      expect(html).to include("[data-theme=dark] .code-highlight")
    end

    it "emits no dark rules when no shipped theme is a dark theme" do
      DocsKit.configure do |c|
        c.themes = %w[light retro]
        c.code_theme_dark = "Rouge::Themes::Github"
      end
      html = described_class.new("puts 'hi'").call

      expect(html).not_to include("[data-theme=")
    end
  end

  it "renders a title bar with the filename when given" do
    html = described_class.new("x = 1", filename: "app/models/x.rb").call

    expect(html).to include("app/models/x.rb")
    expect(html).to include("font-mono")
  end

  # The Markdown export (DocsKit::MarkdownExport) reads the resolved Rouge lexer
  # tag off the highlight wrapper to emit a ```lang fenced block. Code stamps it
  # as data-md-lang so the converter never has to re-resolve the language.
  describe "data-md-lang (the Markdown-export fence hint)" do
    it "stamps the resolved lexer tag on the highlight wrapper" do
      html = described_class.new("puts 'hi'", lexer: :ruby).call

      expect(html).to include('data-md-lang="ruby"')
    end

    it "reflects the actual resolved language, not the requested alias" do
      DocsKit.configure { |c| c.code_lexer_aliases = { fancy: "ruby" } }
      html = described_class.new("puts 'hi'", lexer: :fancy).call

      # The alias resolves to ruby — the hint carries the real Rouge tag.
      expect(html).to include('data-md-lang="ruby"')
    end

    it "stamps plaintext when the language is unknown (fence stays language-less)" do
      html = described_class.new("anything", lexer: :nope).call

      expect(html).to include('data-md-lang="plaintext"')
    end
  end

  # `filename:` selects the language when `lexer:` is not given — the natural
  # `DocsUI::Code(<<~YAML, filename: "config/deploy.yml")` highlights as YAML
  # instead of silently lexing as Ruby.
  describe "lexer inference from filename:" do
    it "guesses the lexer from the filename extension" do
      html = described_class.new("foo: bar\nbaz: [1, 2]", filename: "config/deploy.yml").call

      expect(html).to include('data-md-lang="yaml"')
      expect(html).not_to include('class="err"')
    end

    it "guesses from a well-known basename (Dockerfile)" do
      resolved = described_class.new("FROM ruby", filename: "Dockerfile").send(:lexer)
      expect(resolved).to be_a(Rouge::Lexers::Docker)
    end

    it "lets an explicit lexer: win over the filename" do
      html = described_class.new("puts 'hi'", filename: "x.yml", lexer: :ruby).call

      expect(html).to include('data-md-lang="ruby"')
    end

    it "falls back to ruby for an unguessable filename" do
      html = described_class.new("puts 'hi'", filename: "notes").call

      expect(html).to include('data-md-lang="ruby"')
    end

    it "still defaults to ruby with no filename and no lexer" do
      html = described_class.new("puts 'hi'").call

      expect(html).to include('data-md-lang="ruby"')
    end
  end

  it "falls back to plaintext for an unknown lexer" do
    html = described_class.new("anything", lexer: :nope).call

    expect(html).to include("code-highlight")
  end

  # "All languages available" — any Rouge lexer resolves by name, no allowlist.
  %i[python go rust elixir kotlin swift java php sql json dockerfile typescript].each do |lang|
    it "resolves the #{lang} lexer from Rouge's full registry" do
      resolved = described_class.new("code", lexer: lang).send(:lexer)
      expect(resolved).to be_a(Rouge::Lexer)
      expect(resolved).not_to be_a(Rouge::Lexers::PlainText)
    end
  end

  it "resolves a configured friendly alias" do
    DocsKit.configure { |c| c.code_lexer_aliases = { fancy: "ruby" } }
    resolved = described_class.new("x", lexer: :fancy).send(:lexer)
    expect(resolved).to be_a(Rouge::Lexers::Ruby)
  end

  it "uses the configured fallback for an unknown language" do
    DocsKit.configure { |c| c.code_lexer_fallback = "ruby" }
    resolved = described_class.new("x", lexer: :totally_unknown_lang).send(:lexer)
    expect(resolved).to be_a(Rouge::Lexers::Ruby)
  end

  it "passes an explicit Rouge lexer class through" do
    resolved = described_class.new("x", lexer: Rouge::Lexers::Python).send(:lexer)
    expect(resolved).to be_a(Rouge::Lexers::Python)
  end
end
