# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "rails/generators"
require "generators/docs_kit/page/page_generator"

# The page generator, like the install generator, never boots Rails — it writes
# a page class under app/views/docs/pages/ and injects a `page` line into the
# registry class, both under destination_root via Thor. We exercise it against a
# throwaway destination root seeded with a Registry-v2 `Doc` class, run the
# generator, and assert the new page file + the mutated registry.
RSpec.describe DocsKit::Generators::PageGenerator do
  let(:destination) { File.join(Dir.tmpdir, "docs-kit-page-spec", "my_app_docs") }

  # A Registry-v2 registry class (the `page` DSL form) — the injection target.
  def registry_v2(*extra_page_lines)
    body = extra_page_lines.map { |l| "  #{l}\n" }.join
    <<~RUBY
      # frozen_string_literal: true

      class Doc
        extend DocsKit::Registry
        path_prefix "/docs"
        view_namespace "Views::Docs::Pages"

      #{body unless body.empty?}end
    RUBY
  end

  # The legacy hash-entries registry — the generator must NOT corrupt this.
  def registry_legacy
    <<~RUBY
      # frozen_string_literal: true

      class Doc
        extend DocsKit::Registry

        entries [
          { slug: "installation", title: "Installation", group: "Guide", view: "Installation" }
        ]
      end
    RUBY
  end

  def seed_registry(source)
    write("app/models/doc.rb", source)
  end

  def write(rel, content)
    path = File.join(destination, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def read(rel) = File.read(File.join(destination, rel))
  def exist?(rel) = File.exist?(File.join(destination, rel))

  # Run the generator quietly. `args` is the CLI arg list (title first, then
  # --flags translated to Thor options via the second Hash).
  def run_generator(args, options = {})
    generator = described_class.new(Array(args), options, destination_root: destination)
    silence_stream { generator.invoke_all }
  end

  def silence_stream
    original = $stdout
    $stdout = File.open(File::NULL, "w")
    yield
  ensure
    $stdout.close
    $stdout = original
  end

  before { FileUtils.rm_rf(destination) }
  after  { FileUtils.rm_rf(destination) }

  describe "the generated page file" do
    before do
      seed_registry(registry_v2)
      run_generator(["Getting Started"], { "group" => "Guide" })
    end

    it "writes the page at app/views/docs/pages/<slug underscored>.rb" do
      expect(exist?("app/views/docs/pages/getting_started.rb")).to be(true)
    end

    it "uses the compact one-line class form (no 8-line module nesting)" do
      src = read("app/views/docs/pages/getting_started.rb")
      expect(src).to include("class Views::Docs::Pages::GettingStarted < DocsUI::Page")
      expect(src).not_to include("module Views")
    end

    it "sets the title, eyebrow (from the group), lead, and a starter Section" do
      src = read("app/views/docs/pages/getting_started.rb")
      expect(src).to include(%(title "Getting Started"))
      expect(src).to include(%(eyebrow "Guide"))
      expect(src).to include("def lead")
      expect(src).to include("def content")
      expect(src).to include("DocsUI::Section(")
      expect(src).to include("md <<~")
    end
  end

  describe "the registry injection (Registry v2)" do
    it "injects a page line into an empty v2 registry" do
      seed_registry(registry_v2)
      run_generator(["Getting Started"], { "group" => "Guide" })

      expect(read("app/models/doc.rb")).to include(%(page "Getting Started", group: "Guide"))
    end

    it "appends after the last existing page line so ordering lands at the group's end" do
      seed_registry(registry_v2(%(page "Installation", group: "Guide")))
      run_generator(["Getting Started"], { "group" => "Guide" })

      doc = read("app/models/doc.rb")
      expect(doc.index(%(page "Installation"))).to be < doc.index(%(page "Getting Started"))
    end
  end

  describe "a grouped registry (blank lines + comments between page groups)" do
    # The layout docs_kit:install itself produces: groups of `page` lines
    # separated by a blank line and a `# comment`. The anchor must be the LAST
    # page line of the FILE, not the last line of every group.
    let(:grouped) do
      <<~RUBY
        # frozen_string_literal: true

        class Doc
          extend DocsKit::Registry
          path_prefix "/docs"
          view_namespace "Views::Docs::Pages"

          # Guide
          page "Installation", group: "Guide"
          page "Configuration", group: "Guide"

          # Deploying
          page "Docker", group: "Deploying"
          page "Tunnel", group: "Deploying"
        end
      RUBY
    end

    before { seed_registry(grouped) }

    it "adds exactly one line, after the last page line of the file" do
      run_generator(["New Page"], { "group" => "Deploying" })

      doc = read("app/models/doc.rb")
      expect(doc.scan(%(page "New Page")).size).to eq(1)
      expect(doc.index(%(page "Tunnel"))).to be < doc.index(%(page "New Page"))
      expect(doc.scan(/^\s*page /).size).to eq(5)
    end

    it "is idempotent on a second run" do
      run_generator(["New Page"], { "group" => "Deploying" })
      run_generator(["New Page"], { "group" => "Deploying", "skip" => true })

      expect(read("app/models/doc.rb").scan(%(page "New Page")).size).to eq(1)
    end
  end

  describe "flag overrides" do
    before { seed_registry(registry_v2) }

    it "respects --slug for the filename and the registry line" do
      run_generator(["OAuth"], { "group" => "Guide", "slug" => "auth" })

      expect(exist?("app/views/docs/pages/oauth.rb")).to be(true) # view still derives from title
      expect(read("app/models/doc.rb")).to include(%(page "OAuth", group: "Guide", slug: "auth"))
    end

    it "respects --view for the class name and filename" do
      run_generator(["OAuth"], { "group" => "Guide", "view" => "OauthGuide" })

      expect(exist?("app/views/docs/pages/oauth_guide.rb")).to be(true)
      expect(read("app/views/docs/pages/oauth_guide.rb"))
        .to include("class Views::Docs::Pages::OauthGuide < DocsUI::Page")
      expect(read("app/models/doc.rb")).to include(%(view: "OauthGuide"))
    end

    it "omits a redundant --slug that equals the derived default from the registry line" do
      run_generator(["Getting Started"], { "group" => "Guide", "slug" => "getting-started" })

      expect(read("app/models/doc.rb")).to include(%(page "Getting Started", group: "Guide"\n))
      expect(read("app/models/doc.rb")).not_to include(%(slug: "getting-started"))
    end

    it "omits a redundant --view that equals the derived default from the registry line" do
      run_generator(["Getting Started"], { "group" => "Guide", "view" => "GettingStarted" })

      expect(read("app/models/doc.rb")).to include(%(page "Getting Started", group: "Guide"\n))
      expect(read("app/models/doc.rb")).not_to include(%(view: "GettingStarted"))
    end

    it "respects --eyebrow over the group default" do
      run_generator(["Getting Started"], { "group" => "Guide", "eyebrow" => "Start here" })

      expect(read("app/views/docs/pages/getting_started.rb")).to include(%(eyebrow "Start here"))
    end

    it "respects --registry to target a differently-named registry class" do
      write("app/models/guide.rb", <<~RUBY)
        # frozen_string_literal: true

        class Guide
          extend DocsKit::Registry
          view_namespace "Views::Docs::Pages"
        end
      RUBY
      run_generator(["Getting Started"], { "group" => "Guide", "registry" => "Guide" })

      expect(read("app/models/guide.rb")).to include(%(page "Getting Started", group: "Guide"))
    end
  end

  describe "a legacy hash-entries registry" do
    before do
      seed_registry(registry_legacy)
      run_generator(["Getting Started"], { "group" => "Guide" })
    end

    it "still writes the page file" do
      expect(exist?("app/views/docs/pages/getting_started.rb")).to be(true)
    end

    it "does NOT mutate the legacy registry (no corruption)" do
      expect(read("app/models/doc.rb")).to eq(registry_legacy)
    end

    it "leaves the legacy registry without a v2 page line" do
      expect(read("app/models/doc.rb")).not_to include(%(page "Getting Started"))
    end
  end

  describe "idempotence" do
    before { seed_registry(registry_v2) }

    it "does not inject a duplicate page line on a second run" do
      run_generator(["Getting Started"], { "group" => "Guide" })
      run_generator(["Getting Started"], { "group" => "Guide", "skip" => true })

      doc = read("app/models/doc.rb")
      expect(doc.scan(%(page "Getting Started", group: "Guide")).size).to eq(1)
    end

    it "does not clobber the existing page file in --skip mode" do
      run_generator(["Getting Started"], { "group" => "Guide" })
      write("app/views/docs/pages/getting_started.rb", "# hand-edited\n")

      run_generator(["Getting Started"], { "group" => "Guide", "skip" => true })

      expect(read("app/views/docs/pages/getting_started.rb")).to eq("# hand-edited\n")
    end
  end
end
