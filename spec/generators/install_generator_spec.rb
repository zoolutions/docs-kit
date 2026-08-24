# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tmpdir"
require "rails/generators"
require "generators/docs_kit/install/install_generator"
require "generators/docs_kit/install/migration"
require "generators/docs_kit/install/migration_registry"

# The install generator never touches a booted Rails app — it only reads/writes
# files under destination_root via Thor. So we exercise it against a throwaway
# destination root: a minimal fake app skeleton (routes.rb, application_controller,
# controllers/index.js, assets.rb) built per-example, run the generator, and assert
# the produced file manifest + key contents.
#
# The generator is fully idempotent — safe on a fresh app AND a years-old site.
# Every step guards against a re-run: `create_initializer` skips a site's edited
# config; `add_routes` skips a route the site already has even when it's written
# with different quotes / `to:` vs `=>`; several methods `say_status(:skip)` when
# a target exists. A `--sync` run does ONLY the additive/wiring steps and prints
# a drift checklist for manual cleanup it can't safely automate.
RSpec.describe DocsKit::Generators::InstallGenerator do
  # A named destination dir so app_brand humanizes deterministically
  # ("my_app_docs" → "My app docs"). Rails isn't booted, so app_brand falls back
  # to the basename of destination_root.
  let(:app_name) { "my_app_docs" }
  let(:destination) { File.join(Dir.tmpdir, "docs-kit-gen-spec", app_name) }

  # A stock Stimulus controllers/index.js: only the eager-load line the generator
  # injects the docs_kit path after.
  def stimulus_index_source
    <<~JS
      import { application } from "controllers/application"
      eagerLoadControllersFrom("controllers", application)
    JS
  end

  # Build a minimal Rails-ish skeleton the generator's injections expect to find.
  def build_skeleton(routes: true, app_controller: true, stimulus_index: true, package_json: nil, rubocop_yml: nil)
    FileUtils.mkdir_p(File.join(destination, "config/initializers"))
    FileUtils.mkdir_p(File.join(destination, "app/controllers"))
    FileUtils.mkdir_p(File.join(destination, "app/javascript/controllers"))

    write("config/initializers/assets.rb", %(Rails.application.config.assets.version = "1.0"\n))
    write("config/routes.rb", "Rails.application.routes.draw do\nend\n") if routes
    if app_controller
      write("app/controllers/application_controller.rb",
            "class ApplicationController < ActionController::Base\nend\n")
    end
    write("app/javascript/controllers/index.js", stimulus_index_source) if stimulus_index
    write("package.json", package_json) if package_json
    write(".rubocop.yml", rubocop_yml) if rubocop_yml
  end

  def write(rel, content)
    path = File.join(destination, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def read(rel) = File.read(File.join(destination, rel))
  def exist?(rel) = File.exist?(File.join(destination, rel))

  # Run the generator quietly against the skeleton. Pass generator options
  # (e.g. `sync: true`) through to the Thor invocation.
  def run_generator(**opts)
    generator = described_class.new([], opts, destination_root: destination)
    capture_stream { generator.invoke_all }
  end

  # Run the generator and RETURN its $stdout (Thor progress + any drift
  # checklist), for asserting on printed drift warnings.
  def capture_generator(**opts)
    generator = described_class.new([], opts, destination_root: destination)
    capture_stream { generator.invoke_all }
  end

  # Thor writes progress to $stdout; capture it so the suite stays quiet AND
  # specs can assert on what was printed. $stdin is closed so an unexpected
  # collision prompt fails fast (EOF) rather than hanging the suite waiting on
  # input — an idempotent generator never prompts, so this never fires in GREEN.
  def capture_stream
    original_out = $stdout
    original_in = $stdin
    $stdout = StringIO.new
    $stdin = StringIO.new("")
    yield
    $stdout.string
  ensure
    $stdout = original_out
    $stdin = original_in
  end

  before { FileUtils.rm_rf(destination) }
  after  { FileUtils.rm_rf(destination) }

  describe "the file manifest" do
    before do
      build_skeleton
      run_generator
    end

    it "creates the config initializers" do
      expect(exist?("config/initializers/docs_kit.rb")).to be(true)
      expect(exist?("config/initializers/phlex.rb")).to be(true)
      expect(exist?("config/initializers/rails_icons.rb")).to be(true)
    end

    it "creates the registry model + controllers + pages" do
      expect(exist?("app/models/doc.rb")).to be(true)
      expect(exist?("app/controllers/docs_controller.rb")).to be(true)
      expect(exist?("app/controllers/landings_controller.rb")).to be(true)
      expect(exist?("app/views/docs/pages/installation.rb")).to be(true)
      expect(exist?("app/views/landings/show.rb")).to be(true)
    end

    it "creates the CSS build files + keeps" do
      expect(exist?("app/assets/stylesheets/application.tailwind.css")).to be(true)
      expect(exist?("bin/build-css")).to be(true)
      expect(exist?("lib/tasks/build_css.rake")).to be(true)
      expect(exist?("app/assets/builds/.keep")).to be(true)
      expect(exist?("app/components/.keep")).to be(true)
    end

    it "installs the docs_kit:og rake task (but ships NO image — that's site content)" do
      expect(exist?("lib/tasks/docs_kit_og.rake")).to be(true)
      # The gem does not vendor an OG image; the task generates one into the
      # site's own app/assets/images/ when run.
      expect(exist?("app/assets/images/og/og.png")).to be(false)
    end

    it "ships an og.rake that defines a docs_kit:og task writing into the site's images dir" do
      rake = read("lib/tasks/docs_kit_og.rake")

      expect(rake).to include("namespace :docs_kit")
      expect(rake).to match(/task\s+og:/)
      expect(rake).to include("app/assets/images/og")
    end
  end

  # The Docker delivery: a gem-owned `.dockerignore` (refreshed every run, like
  # the og rake task) and a site-customizable `Dockerfile` (skip-if-exists, like
  # the config initializer). The Dockerfile carries a version marker so a `--sync`
  # upgrade can flag it as stale against the gem's current template.
  describe "Docker files (create_dockerfile + create_dockerignore)" do
    before do
      build_skeleton
      run_generator
    end

    it "creates a Dockerfile and a .dockerignore" do
      expect(exist?("Dockerfile")).to be(true)
      expect(exist?(".dockerignore")).to be(true)
    end

    it "stamps the Dockerfile with the gem's version marker (so a --sync can detect staleness)" do
      dockerfile = read("Dockerfile")

      expect(dockerfile).to include("docs-kit Dockerfile v#{DocsKit::VERSION}")
    end

    it "writes a standalone-site Dockerfile (WORKDIR /rails, whole-app context)" do
      dockerfile = read("Dockerfile")

      # A consuming site is a standalone Rails app at the context root — NOT the
      # gem's /app + /app/docs monorepo layout.
      expect(dockerfile).to include("WORKDIR /rails")
      expect(dockerfile).to include("COPY --from=build /rails /rails")
      expect(dockerfile).not_to include("/app/docs")
    end

    it "uses a multi-stage build that keeps build tooling out of the final image" do
      dockerfile = read("Dockerfile")

      expect(dockerfile).to include("FROM base AS build")
      # build-essential/git/pkg-config are build-stage only; the final stage
      # copies just the bundle + app from the build stage.
      expect(dockerfile).to include("build-essential")
      expect(dockerfile).to include(%(COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"))
    end

    it "excludes build cruft in .dockerignore (node_modules, git, logs, tmp, specs, coverage)" do
      dockerignore = read(".dockerignore")

      %w[node_modules .git log tmp spec coverage].each do |pattern|
        expect(dockerignore).to include(pattern)
      end
    end

    it "keeps the built assets and the lockfile OUT of .dockerignore (the build needs them)" do
      dockerignore = read(".dockerignore")

      # Gemfile.lock is required for a reproducible `bundle install --frozen`.
      expect(dockerignore).not_to match(/^\s*Gemfile\.lock\s*$/)
    end

    it "falls back to a plain rails server CMD when the site has no Thruster" do
      # The default skeleton has no bin/thrust and no Gemfile — a thrust CMD
      # would crash the container at boot (Gem.bin_path raises), so the plain
      # server CMD is the only safe default.
      dockerfile = read("Dockerfile")

      expect(dockerfile).to include(%(CMD ["./bin/rails", "server", "-b", "0.0.0.0"]))
      expect(dockerfile).not_to include(%(CMD ["./bin/thrust"))
    end

    it "does not clobber a site's customized Dockerfile on re-run (site-owned, skip-if-exists)" do
      write("Dockerfile", "# my hand-tuned Dockerfile\nFROM ruby:3.2\n")

      run_generator

      expect(read("Dockerfile")).to eq("# my hand-tuned Dockerfile\nFROM ruby:3.2\n")
    end

    it "refreshes the gem-owned .dockerignore on re-run (not site-owned)" do
      write(".dockerignore", "# stale\n")

      run_generator

      expect(read(".dockerignore")).to include("node_modules")
      expect(read(".dockerignore")).not_to eq("# stale\n")
    end
  end

  # Thruster (HTTP caching + compression + X-Sendfile in front of Puma) is used
  # when the site actually bundles it — a `rails new` on Rails 8 ships
  # `gem "thruster"` + bin/thrust, but docs_kit:install also runs on older apps
  # where a thrust CMD would crash the container at boot. Detection: bin/thrust
  # OR a Gemfile thruster entry.
  describe "Dockerfile Thruster CMD (thruster-aware sites)" do
    context "when the site has a bin/thrust binstub" do
      before do
        build_skeleton
        write("bin/thrust", "#!/usr/bin/env ruby\nload Gem.bin_path(\"thruster\", \"thrust\")\n")
        run_generator
      end

      it "fronts Puma with Thruster" do
        expect(read("Dockerfile")).to include(%(CMD ["./bin/thrust", "./bin/rails", "server"]))
      end

      it "pins HTTP_PORT to 3000 (kamal-proxy's app_port; non-root can't rely on 80)" do
        dockerfile = read("Dockerfile")

        # Thruster's default HTTP_PORT is 80: as USER 1000 the bind can fail, and
        # kamal-proxy routes to app_port 3000 — which would hit Puma directly and
        # silently bypass Thruster. HTTP_PORT=3000 keeps Thruster on the routed
        # port; TARGET_PORT moves Puma out of the way.
        expect(dockerfile).to match(/HTTP_PORT="?3000"?/)
        expect(dockerfile).to match(/TARGET_PORT="?3001"?/)
      end

      it "does not also emit the plain-server fallback CMD" do
        expect(read("Dockerfile")).not_to include(%(CMD ["./bin/rails", "server", "-b", "0.0.0.0"]))
      end
    end

    context "when the site's Gemfile bundles thruster (no binstub yet)" do
      before do
        build_skeleton
        write("Gemfile", <<~RUBY)
          source "https://rubygems.org"
          gem "rails"
          gem "thruster", require: false
        RUBY
        run_generator
      end

      it "fronts Puma with Thruster" do
        expect(read("Dockerfile")).to include(%(CMD ["./bin/thrust", "./bin/rails", "server"]))
      end

      it "creates the bin/thrust binstub the CMD needs (or the container crashes at boot)" do
        # `bundle install` installs the gem, not app binstubs, and `COPY . .` can't
        # copy a file the repo doesn't have — an exec-form CMD pointing at a
        # missing ./bin/thrust builds green and then dies at container start.
        expect(exist?("bin/thrust")).to be(true)
        expect(read("bin/thrust")).to include(%(Gem.bin_path("thruster", "thrust")))

        mode = File.stat(File.join(destination, "bin/thrust")).mode & 0o777
        expect(mode).to eq(0o755)
      end
    end

    context "when the site already has its own bin/thrust" do
      before do
        build_skeleton
        write("bin/thrust", "#!/usr/bin/env ruby\n# hand-tuned\nload Gem.bin_path(\"thruster\", \"thrust\")\n")
        run_generator
      end

      it "never overwrites the existing binstub" do
        expect(read("bin/thrust")).to include("# hand-tuned")
      end
    end

    context "when thruster is only in a group BUNDLE_WITHOUT excludes" do
      before do
        build_skeleton
        write("Gemfile", <<~RUBY)
          source "https://rubygems.org"
          gem "rails"

          group :development do
            gem "thruster", require: false
          end
        RUBY
        run_generator
      end

      it "keeps the plain rails server CMD (the production bundle won't have the gem)" do
        # BUNDLE_WITHOUT="development:test" means Gem.bin_path("thruster") raises
        # at boot — a dev-group entry must NOT trigger the thrust CMD.
        dockerfile = read("Dockerfile")

        expect(dockerfile).to include(%(CMD ["./bin/rails", "server", "-b", "0.0.0.0"]))
        expect(dockerfile).not_to include(%(CMD ["./bin/thrust"))
      end

      it "does not scaffold a binstub for a gem the production bundle excludes" do
        expect(exist?("bin/thrust")).to be(false)
      end
    end

    context "when thruster uses the inline group: kwarg" do
      before do
        build_skeleton
        write("Gemfile", <<~RUBY)
          source "https://rubygems.org"
          gem "rails"
          gem "thruster", require: false, group: :development
        RUBY
        run_generator
      end

      it "keeps the plain rails server CMD" do
        expect(read("Dockerfile")).to include(%(CMD ["./bin/rails", "server", "-b", "0.0.0.0"]))
        expect(read("Dockerfile")).not_to include(%(CMD ["./bin/thrust"))
      end
    end

    context "when the site's Gemfile has no thruster" do
      before do
        build_skeleton
        write("Gemfile", <<~RUBY)
          source "https://rubygems.org"
          gem "rails"
        RUBY
        run_generator
      end

      it "keeps the plain rails server CMD" do
        dockerfile = read("Dockerfile")

        expect(dockerfile).to include(%(CMD ["./bin/rails", "server", "-b", "0.0.0.0"]))
        expect(dockerfile).not_to include(%(CMD ["./bin/thrust"))
      end
    end
  end

  describe "config/initializers/docs_kit.rb" do
    before do
      build_skeleton
      run_generator
    end

    it "substitutes the humanized app name as the brand" do
      initializer = read("config/initializers/docs_kit.rb")

      expect(initializer).to include(%(c.brand        = "My app docs"))
      expect(initializer).to include(%(c.title_suffix = "My app docs"))
    end

    it "ships the theme list that matches the Tailwind @plugin block" do
      css = read("app/assets/stylesheets/application.tailwind.css")
      initializer = read("config/initializers/docs_kit.rb")

      %w[dark light synthwave retro cyberpunk dracula night nord sunset].each do |theme|
        expect(initializer).to include(theme)
        expect(css).to include(theme)
      end
    end

    it "documents the optional OpenAPI-bridge knob (commented, so it's opt-in)" do
      initializer = read("config/initializers/docs_kit.rb")

      # Commented by default — a site that doesn't maintain a spec is unaffected.
      expect(initializer).to include("# c.openapi = ")
      expect(initializer).to match(/openapi\.ya?ml/)
    end

    it "documents the optional app_link knob (commented, so it's opt-in)" do
      initializer = read("config/initializers/docs_kit.rb")

      # Commented by default — a standalone docs site has no app to link back to.
      expect(initializer).to include("# c.app_link = ")
      expect(initializer).to include("Back to the app")
    end

    it "documents the optional brand_logo + topbar_brand knobs (commented, so they're opt-in)" do
      initializer = read("config/initializers/docs_kit.rb")

      # Commented by default — the text brand renders until a site opts in.
      expect(initializer).to include("# c.brand_logo = ")
      expect(initializer).to include("# c.topbar_brand = :mobile_only")
      expect(initializer).to include("currentColor")
    end

    it "documents the optional topbar_links knob (commented, so it's opt-in)" do
      initializer = read("config/initializers/docs_kit.rb")

      # Commented by default — a site with no repo/social links is unchanged.
      expect(initializer).to include("# c.topbar_links = ")
      expect(initializer).to include(":github")
    end

    it "documents the SEO/social-share knobs (commented, so they're opt-in)" do
      initializer = read("config/initializers/docs_kit.rb")

      # Commented by default — a site that sets none still renders a valid head.
      expect(initializer).to include("# c.seo.description")
      expect(initializer).to include("# c.seo.og_image")
      expect(initializer).to include("# c.seo.twitter_site")
      # Points the site owner at the regeneration command for the OG image.
      expect(initializer).to include("docs_kit:og")
    end
  end

  # The initializer is the ONE file a site is expected to edit heavily (brand,
  # themes, nav). Re-running the generator (the sanctioned upgrade path) must
  # NEVER clobber it — a re-run skips it and points the upgrader at the current
  # template for a manual diff.
  describe "config/initializers/docs_kit.rb is never clobbered on re-run" do
    let(:edited_config) do
      <<~RUBY
        # frozen_string_literal: true
        DocsKit.configure do |c|
          c.brand = "My Hand-Edited Brand"
          c.themes = %w[my-custom-theme]
        end
      RUBY
    end

    before do
      build_skeleton
      run_generator
      # Simulate a site heavily editing its config after the first install.
      write("config/initializers/docs_kit.rb", edited_config)
    end

    it "preserves the site's edited config body on re-run (only prepends the inert version stamp)" do
      run_generator

      result = read("config/initializers/docs_kit.rb")
      # The edited config body is untouched — just prefixed with the synced-version
      # stamp comment (an inert line the migration machinery reads on the next sync).
      expect(result).to include(edited_config.rstrip)
      expect(result).to eq("# docs-kit synced: v#{DocsKit::VERSION}\n#{edited_config}")
    end

    it "reports the skip and hints at the template for an upgrade diff" do
      output = capture_generator

      expect(output).to include("docs_kit.rb")
      expect(output).to match(/skip|exist/i)
    end
  end

  describe "route injection (add_routes)" do
    before do
      build_skeleton
      run_generator
    end

    it "adds the docs and root routes" do
      routes = read("config/routes.rb")

      expect(routes).to include(%(get "docs/:doc(.:format)" => "docs#show", as: :doc))
      expect(routes).to include(%(root "landings#show"))
    end

    it "allows an optional .:format on the docs route (so /docs/x.md serves the twin)" do
      routes = read("config/routes.rb")

      # The Markdown twin (GET /docs/x.md) needs the format segment enabled. The
      # docs route explicitly opts it in and must NOT pin format: 'html'.
      expect(routes).to include("(.:format)")
      expect(routes).not_to match(/defaults:\s*\{\s*format:/)
    end

    it "adds the llms.txt + llms-full.txt routes (AI-readable docs)" do
      routes = read("config/routes.rb")

      expect(routes).to include(%(get "/llms.txt" => "docs_kit/llms#index"))
      expect(routes).to include(%(get "/llms-full.txt" => "docs_kit/llms#full"))
    end

    it "adds the docs-search route (matches the default c.search_path)" do
      routes = read("config/routes.rb")

      expect(routes).to include(%(get "/docs/search" => "docs_kit/search#index"))
    end

    it "adds the MCP route COMMENTED OUT (opt-in: needs the optional mcp gem)" do
      routes = read("config/routes.rb")

      # The MCP endpoint is off by default (the `mcp` gem is optional). The
      # generator draws the route commented so a site opts in by uncommenting.
      expect(routes).to include(%(# post "/mcp" => "docs_kit/mcp#create"))
      expect(routes).to include(%(# match "/mcp" => "docs_kit/mcp#method_not_allowed", via: %i[get delete]))
    end

    it "does not re-inject the commented MCP scaffold when the site has LIVE /mcp routes" do
      # A site that opted in (uncommented, in its own style — an `, as: :mcp`
      # suffix) must not accumulate the commented scaffold on every --sync run.
      # Found dogfooding 1.0.3 into pgbus + phlex-reactive.
      write("config/routes.rb", <<~ROUTES)
        Rails.application.routes.draw do
          post "/mcp" => "docs_kit/mcp#create", as: :mcp
          match "/mcp" => "docs_kit/mcp#method_not_allowed", via: %i[get delete]
        end
      ROUTES

      run_generator(sync: true)

      routes = read("config/routes.rb")
      expect(routes).not_to include(%(# post "/mcp"))
      expect(routes).not_to include(%(# match "/mcp"))
      expect(routes.scan(%r{docs_kit/mcp#create}).size).to eq(1)
    end

    it "draws /docs/search ABOVE docs/:doc so it isn't swallowed as :doc" do
      routes = read("config/routes.rb")

      search_at = routes.index(%(get "/docs/search" => "docs_kit/search#index"))
      doc_at = routes.index(%(get "docs/:doc(.:format)" => "docs#show"))
      expect(search_at).to be < doc_at
    end

    it "does not duplicate routes on re-run (idempotent)" do
      run_generator # second invocation against the same destination

      routes = read("config/routes.rb")
      expect(routes.scan(%(get "/llms.txt" => "docs_kit/llms#index")).size).to eq(1)
      expect(routes.scan(%(get "/llms-full.txt" => "docs_kit/llms#full")).size).to eq(1)
      expect(routes.scan(%(get "docs/:doc(.:format)" => "docs#show", as: :doc)).size).to eq(1)
      expect(routes.scan(%(get "/docs/search" => "docs_kit/search#index")).size).to eq(1)
    end
  end

  # A years-old site wrote its routes by hand, in its OWN style (single quotes,
  # `to:` instead of `=>`, no `.:format`). Thor's `route` only skips a
  # byte-identical line, so a naive re-run would DUPLICATE these. The guard
  # matches on the route's controller#action (quote/arrow/whitespace tolerant),
  # so re-running is a genuine no-op.
  describe "route idempotency against a hand-written (differently-styled) routes.rb" do
    let(:handwritten_routes) do
      <<~ROUTES
        Rails.application.routes.draw do
          root 'landings#show'
          get 'docs/:doc' => 'docs#show', as: :doc
          get '/docs/search', to: 'docs_kit/search#index', as: :docs_search
        end
      ROUTES
    end

    before do
      build_skeleton
      write("config/routes.rb", handwritten_routes)
      run_generator
    end

    it "does not add a second root route" do
      expect(read("config/routes.rb").scan(/root\b/).size).to eq(1)
    end

    it "does not add a second docs#show route" do
      expect(read("config/routes.rb").scan(/["']docs#show["']/).size).to eq(1)
    end

    it "does not add a second docs_kit/search#index route" do
      expect(read("config/routes.rb").scan(%r{docs_kit/search#index}).size).to eq(1)
    end

    it "leaves the site's hand-written route syntax untouched" do
      # We warn about drift, we never rewrite a route the site already drew.
      expect(read("config/routes.rb")).to include(%(get 'docs/:doc' => 'docs#show', as: :doc))
    end
  end

  describe "controller injection (include_controller_helper)" do
    it "injects include DocsKit::Controller into ApplicationController" do
      build_skeleton
      run_generator

      expect(read("app/controllers/application_controller.rb"))
        .to include("include DocsKit::Controller")
    end

    it "skips injection when ApplicationController is absent" do
      build_skeleton(app_controller: false)
      run_generator

      expect(exist?("app/controllers/application_controller.rb")).to be(false)
    end
  end

  describe "asset paths + package.json (wire_assets_and_package_json)" do
    it "appends the builds path to config/initializers/assets.rb" do
      build_skeleton
      run_generator

      expect(read("config/initializers/assets.rb"))
        .to include(%(Rails.application.config.assets.paths << Rails.root.join("app", "assets", "builds")))
    end

    it "creates a package.json stub with the build:css scripts when none exists" do
      build_skeleton
      run_generator

      package = read("package.json")
      expect(package).to include(%("build:css": "bin/build-css --minify"))
      expect(package).to include(%("watch:css": "bin/build-css --watch"))
    end

    it "does not overwrite an existing package.json that already has build:css" do
      existing = %({\n  "scripts": { "build:css": "custom" }\n}\n)
      build_skeleton(package_json: existing)
      run_generator

      expect(read("package.json")).to eq(existing)
    end
  end

  describe "Stimulus registration (register_stimulus_controller)" do
    it "registers the docs_kit controllers path in controllers/index.js" do
      build_skeleton
      run_generator

      expect(read("app/javascript/controllers/index.js"))
        .to include(%(eagerLoadControllersFrom("docs_kit/controllers", application)))
    end

    it "skips registration when there is no controllers/index.js" do
      build_skeleton(stimulus_index: false)
      run_generator

      expect(exist?("app/javascript/controllers/index.js")).to be(false)
    end

    it "does not double-register when the site already lazy-loads the docs_kit path" do
      # A years-old site wired the docs-nav controller with lazyLoadControllersFrom
      # (valid — the engine auto-pins it). Re-running must NOT add a second, eager
      # registration on top.
      build_skeleton(stimulus_index: false)
      write("app/javascript/controllers/index.js", <<~JS)
        import { application } from "controllers/application"
        import { eagerLoadControllersFrom, lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
        eagerLoadControllersFrom("controllers", application)
        lazyLoadControllersFrom("docs_kit/controllers", application)
      JS

      run_generator

      index = read("app/javascript/controllers/index.js")
      expect(index.scan("docs_kit/controllers").size).to eq(1)
      expect(index).to include(%(lazyLoadControllersFrom("docs_kit/controllers", application)))
    end

    it "does not append an unimported eager line to a lazy-only index.js" do
      # A lazy-only index.js (stock stimulus-loading, no eagerLoadControllersFrom
      # import) has no eager anchor to inject after. Appending the eager REGISTER_LINE
      # would call eagerLoadControllersFrom with no import — a ReferenceError that
      # aborts the module and registers ZERO controllers. Warn instead.
      build_skeleton(stimulus_index: false)
      write("app/javascript/controllers/index.js", <<~JS)
        import { application } from "controllers/application"
        import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
        lazyLoadControllersFrom("controllers", application)
      JS

      run_generator

      index = read("app/javascript/controllers/index.js")
      expect(index).not_to include("eagerLoadControllersFrom")
    end
  end

  describe "bin/build-css" do
    it "is created executable (chmod 0755)" do
      build_skeleton
      run_generator

      mode = File.stat(File.join(destination, "bin/build-css")).mode & 0o777
      expect(mode).to eq(0o755)
    end
  end

  # The AI-authoring scaffold: an AGENTS.md (the cross-tool authoring contract)
  # and a Claude Code skill (.claude/skills/write-docs-page/SKILL.md). Both are
  # brand-substituted; AGENTS.md is injected between delimiters when one already
  # exists (user content preserved); the skill file is skipped when present.
  describe "AI-authoring scaffold (create_agent_docs)" do
    # The delimiters bounding the injected block in a pre-existing AGENTS.md.
    let(:begin_marker) { "<!-- BEGIN docs-kit -->" }
    let(:end_marker) { "<!-- END docs-kit -->" }

    context "when neither file exists" do
      before do
        build_skeleton
        run_generator
      end

      it "creates AGENTS.md at the site root" do
        expect(exist?("AGENTS.md")).to be(true)
      end

      it "creates the write-docs-page Claude Code skill" do
        expect(exist?(".claude/skills/write-docs-page/SKILL.md")).to be(true)
      end

      it "substitutes the humanized app brand into AGENTS.md" do
        expect(read("AGENTS.md")).to include("My app docs")
      end

      it "encodes the core authoring idioms in AGENTS.md" do
        agents = read("AGENTS.md")

        # The one-command page flow and the md-first prose idiom — the two
        # things an agent must know before it writes a page.
        expect(agents).to include("rails g docs_kit:page")
        expect(agents).to include("md <<~'MD'")
        # The invariant an agent must not break.
        expect(agents).to include("DocsUI::Section")
      end

      it "wraps the AGENTS.md body in the docs-kit delimiters (so a re-run can find it)" do
        agents = read("AGENTS.md")

        expect(agents).to include(begin_marker)
        expect(agents).to include(end_marker)
      end

      it "targets write/add/update documentation in the skill frontmatter" do
        skill = read(".claude/skills/write-docs-page/SKILL.md")

        expect(skill).to match(/^---$/) # YAML frontmatter present
        expect(skill).to match(/description:.*document/i)
        expect(skill).to include("rails g docs_kit:page")
      end
    end

    context "when AGENTS.md already exists with user content" do
      let(:user_content) { "# My project\n\nHand-written guidance the user owns.\n" }

      before do
        build_skeleton
        write("AGENTS.md", user_content)
        run_generator
      end

      it "preserves the user's existing content" do
        expect(read("AGENTS.md")).to include("Hand-written guidance the user owns.")
      end

      it "injects the docs-kit block between delimiters" do
        agents = read("AGENTS.md")

        expect(agents).to include(begin_marker)
        expect(agents).to include(end_marker)
        expect(agents).to include("rails g docs_kit:page")
      end
    end

    context "when re-run (idempotence)" do
      before do
        build_skeleton
        run_generator
        run_generator # second invocation against the same destination
      end

      it "does not duplicate the docs-kit block in AGENTS.md" do
        agents = read("AGENTS.md")

        expect(agents.scan(begin_marker).size).to eq(1)
        expect(agents.scan(end_marker).size).to eq(1)
      end

      it "leaves a hand-edited AGENTS.md's user sections intact" do
        # Simulate a user editing OUTSIDE the delimited block after install.
        agents = read("AGENTS.md")
        edited = "#{agents}\n## My own section\n\nDo not clobber me.\n"
        write("AGENTS.md", edited)

        run_generator

        result = read("AGENTS.md")
        expect(result).to include("Do not clobber me.")
        expect(result.scan(begin_marker).size).to eq(1)
      end
    end

    context "when the skill file already exists" do
      before do
        build_skeleton
        write(".claude/skills/write-docs-page/SKILL.md", "# custom skill, do not clobber\n")
        run_generator
      end

      it "does not overwrite the existing skill" do
        expect(read(".claude/skills/write-docs-page/SKILL.md")).to eq("# custom skill, do not clobber\n")
      end
    end
  end

  # The RuboCop wiring: the site's .rubocop.yml gets `require: docs_kit/rubocop`
  # and `inherit_gem: { docs-kit: config/rubocop/docs_kit.yml }` so the gem's
  # cops run. Created minimal when absent; merged (not clobbered) into an
  # existing one; idempotent on re-run.
  describe "RuboCop cop wiring (wire_rubocop_cops)" do
    def rubocop_config
      require "yaml"
      YAML.safe_load(read(".rubocop.yml"))
    end

    context "when the site has no .rubocop.yml" do
      before do
        build_skeleton
        run_generator
      end

      it "creates one that requires the gem cop entry point" do
        expect(rubocop_config["require"]).to include("docs_kit/rubocop")
      end

      it "inherits the shipped cop config from the gem" do
        expect(rubocop_config.dig("inherit_gem", "docs-kit")).to include("config/rubocop/docs_kit.yml")
      end
    end

    context "when the site already has a .rubocop.yml (e.g. rails new omakase)" do
      let(:omakase) do
        <<~YAML
          # Omakase Ruby styling for Rails
          inherit_gem: { rubocop-rails-omakase: rubocop.yml }
        YAML
      end

      before do
        build_skeleton(rubocop_yml: omakase)
        run_generator
      end

      it "adds the docs-kit cop require without dropping the existing inherit_gem" do
        config = rubocop_config
        expect(config["require"]).to include("docs_kit/rubocop")
        expect(config.dig("inherit_gem", "rubocop-rails-omakase")).to eq("rubocop.yml")
        expect(config.dig("inherit_gem", "docs-kit")).to include("config/rubocop/docs_kit.yml")
      end
    end

    context "when the site's .rubocop.yml already has a require list" do
      let(:existing) do
        <<~YAML
          require:
            - rubocop-rspec
          AllCops:
            NewCops: enable
        YAML
      end

      before do
        build_skeleton(rubocop_yml: existing)
        run_generator
      end

      it "appends to the existing require list rather than replacing it" do
        requires = rubocop_config["require"]
        expect(requires).to include("rubocop-rspec")
        expect(requires).to include("docs_kit/rubocop")
      end
    end

    context "when re-run (idempotence)" do
      before do
        build_skeleton
        run_generator
        run_generator
      end

      it "does not duplicate the docs_kit/rubocop require" do
        expect(rubocop_config["require"].count("docs_kit/rubocop")).to eq(1)
      end

      it "does not duplicate the docs-kit inherit_gem entry" do
        expect(rubocop_config.dig("inherit_gem", "docs-kit").count("config/rubocop/docs_kit.yml")).to eq(1)
      end
    end
  end

  # `--sync` is the documented upgrade path for an existing site: it runs ONLY
  # the additive/wiring steps (routes, initializer hint, importmap/stimulus,
  # AGENTS.md, .rubocop.yml) and prints a checklist of manual drift it detected.
  # It never scaffolds site content (the doc registry, pages, the CSS build) —
  # those already exist and are site-owned — and it never overwrites site files,
  # so a re-run causes ZERO Thor conflict prompts.
  describe "--sync mode (the upgrade path for an existing site)" do
    context "when the site already has the chrome files" do
      before do
        build_skeleton
        run_generator # first, full install
        run_generator(sync: true) # then a sync run
      end

      it "does not re-scaffold the docs registry or pages" do
        # Delete a site-owned file, then sync: sync must NOT recreate it.
        FileUtils.rm(File.join(destination, "app/models/doc.rb"))
        FileUtils.rm(File.join(destination, "app/views/docs/pages/installation.rb"))

        run_generator(sync: true)

        expect(exist?("app/models/doc.rb")).to be(false)
        expect(exist?("app/views/docs/pages/installation.rb")).to be(false)
      end

      it "does not re-scaffold the site-owned CSS build" do
        FileUtils.rm(File.join(destination, "app/assets/stylesheets/application.tailwind.css"))

        run_generator(sync: true)

        expect(exist?("app/assets/stylesheets/application.tailwind.css")).to be(false)
      end

      it "still keeps the wiring in place (routes, stimulus, rubocop)" do
        routes = read("config/routes.rb")
        expect(routes).to include(%(get "docs/:doc(.:format)" => "docs#show", as: :doc))
        expect(read("app/javascript/controllers/index.js"))
          .to include(%(eagerLoadControllersFrom("docs_kit/controllers", application)))
        expect(read(".rubocop.yml")).to include("docs_kit/rubocop")
      end
    end

    context "when run on a fresh skeleton (no prior full install)" do
      before { build_skeleton }

      it "wires routes without scaffolding site content" do
        run_generator(sync: true)

        # Wiring happened...
        expect(read("config/routes.rb")).to include(%("docs#show"))
        # ...but no site-owned content was scaffolded.
        expect(exist?("app/models/doc.rb")).to be(false)
        expect(exist?("app/views/docs/pages/installation.rb")).to be(false)
      end

      it "is idempotent: a second sync duplicates no routes" do
        run_generator(sync: true)
        run_generator(sync: true)

        routes = read("config/routes.rb")
        expect(routes.scan(%(get "docs/:doc(.:format)" => "docs#show", as: :doc)).size).to eq(1)
      end
    end
  end

  # Drift detection: `--sync` reads the site (string-level, conservatively) and
  # warns about manual cleanup it can NOT safely automate — a hand-written
  # `render_page` (DocsKit::Controller now provides it) and a dead `IconHelper`
  # copy. It warns, never deletes, and always exits zero.
  describe "--sync drift detection" do
    # An ApplicationController that hand-defines render_page (the pre-generator
    # pattern) — the audit's #1 drift item.
    def seed_handwritten_render_page
      write("app/controllers/application_controller.rb", <<~RUBY)
        class ApplicationController < ActionController::Base
          include DocsKit::Controller

          private

          def render_page(view)
            render view, layout: false
          end
        end
      RUBY
    end

    it "warns when ApplicationController hand-defines render_page" do
      build_skeleton
      seed_handwritten_render_page

      output = capture_generator(sync: true)

      expect(output).to include("render_page")
      expect(output).to include("DocsKit::Controller")
    end

    it "warns when a dead IconHelper copy is present" do
      build_skeleton
      write("app/helpers/icon_helper.rb", "module IconHelper\nend\n")

      output = capture_generator(sync: true)

      expect(output).to include("IconHelper")
    end

    it "does NOT delete the drifted files (warn, never auto-delete)" do
      build_skeleton
      seed_handwritten_render_page
      write("app/helpers/icon_helper.rb", "module IconHelper\nend\n")

      capture_generator(sync: true)

      expect(exist?("app/controllers/application_controller.rb")).to be(true)
      expect(read("app/controllers/application_controller.rb")).to include("def render_page")
      expect(exist?("app/helpers/icon_helper.rb")).to be(true)
    end

    it "reports a clean bill on a site with no drift" do
      build_skeleton
      run_generator # full install: ApplicationController only gets `include`, no render_page

      output = capture_generator(sync: true)

      expect(output).not_to include("render_page")
      expect(output).not_to include("IconHelper")
    end

    it "warns when the site's Dockerfile is stamped with an older docs-kit version" do
      build_skeleton
      # A site scaffolded by an older docs-kit carries an older version marker.
      write("Dockerfile", "# docs-kit Dockerfile v0.9.0\nFROM ruby:3.4-slim\n")

      output = capture_generator(sync: true)

      expect(output).to include("Dockerfile")
      expect(output).to include("0.9.0")
      expect(output).to include(DocsKit::VERSION)
    end

    it "does NOT warn when the site's Dockerfile marker matches the gem version" do
      build_skeleton
      write("Dockerfile", "# docs-kit Dockerfile v#{DocsKit::VERSION}\nFROM ruby:3.4-slim\n")

      output = capture_generator(sync: true)

      expect(output).not_to match(/Dockerfile.*older|stale.*Dockerfile/i)
    end

    it "does NOT warn about a Dockerfile with no docs-kit marker (site brought its own)" do
      build_skeleton
      write("Dockerfile", "FROM ruby:3.4-slim\n# a hand-written Dockerfile, no marker\n")

      output = capture_generator(sync: true)

      expect(output).not_to match(/Dockerfile is v|Dockerfile.*older/i)
    end
  end

  # Fleet convention (#71): bin/build-css regenerates tailwind.sources.css on
  # every build with machine-specific absolute gem paths — committed, it churns
  # per machine/Ruby and no build consumes the committed copy. The generator
  # gitignores it (additive, idempotent, runs under --sync too); untracking an
  # already-committed copy is warned via the drift report, never automated.
  describe "gitignoring the generated tailwind.sources.css" do
    let(:sources_path) { "app/assets/stylesheets/tailwind.sources.css" }

    it "appends the ignore entry to an existing .gitignore" do
      build_skeleton
      write(".gitignore", "/node_modules\n")

      run_generator

      gitignore = read(".gitignore")
      expect(gitignore).to include("/node_modules")
      expect(gitignore).to match(%r{^/#{Regexp.escape(sources_path)}$})
    end

    it "creates a .gitignore carrying the entry when the site has none" do
      build_skeleton

      run_generator

      expect(read(".gitignore")).to match(%r{^/#{Regexp.escape(sources_path)}$})
    end

    it "is idempotent — a re-run adds no duplicate entry" do
      build_skeleton
      run_generator
      run_generator

      expect(read(".gitignore").scan(sources_path).size).to eq(1)
    end

    it "tolerates a hand-added entry without a leading slash (no duplicate)" do
      build_skeleton
      write(".gitignore", "#{sources_path}\n")

      run_generator

      expect(read(".gitignore").scan(sources_path).size).to eq(1)
    end

    it "treats a bare-filename ignore line as covering (matches at any depth — no duplicate)" do
      build_skeleton
      write(".gitignore", "tailwind.sources.css\n")

      run_generator

      expect(read(".gitignore")).to eq("tailwind.sources.css\n")
    end

    it "respects a site's explicit negation (!) — never appends an override" do
      # A site that deliberately unignores + commits the file has opted out of
      # the fleet convention. Appending our entry would become the LAST matching
      # rule and silently defeat the hand-edit — so the generator backs off.
      build_skeleton
      write(".gitignore", "app/assets/stylesheets/*\n!/#{sources_path}\n")

      output = capture_generator

      expect(read(".gitignore")).to eq("app/assets/stylesheets/*\n!/#{sources_path}\n")
      expect(output).to match(/negat|opt-out/i)
    end

    it "recognizes an existing entry on a CRLF .gitignore (no duplicate per re-run)" do
      build_skeleton
      write(".gitignore", "/#{sources_path}\r\n")

      run_generator

      expect(read(".gitignore")).to eq("/#{sources_path}\r\n")
    end

    it "honors last-match-wins: a dead negation followed by an ignore line is NOT an opt-out" do
      # git reads the LAST matching line — a later ignore rule overrides the
      # negation, so the file is effectively ignored: no append needed, and the
      # tracked-file drift warning must still fire.
      build_skeleton
      write(".gitignore", "!#{sources_path}\n/#{sources_path}\n")
      write(sources_path, "/* tracked while effectively ignored */\n")
      system("git", "-C", destination, "init", "-q")
      system("git", "-C", destination, "add", "-f", sources_path)

      output = capture_generator(sync: true)

      expect(read(".gitignore")).to eq("!#{sources_path}\n/#{sources_path}\n")
      expect(output).to include("git rm --cached #{sources_path}")
    end

    it "still warns when a dead negation precedes an UNRECOGNIZED broad ignore (git's verdict wins)" do
      # The recognized-lines regex can't see `app/assets/stylesheets/*`, but the
      # drift check asks git itself — git says the file is effectively ignored,
      # so the negation is dead and the tracked copy still gets the nag.
      build_skeleton
      write(".gitignore", "!#{sources_path}\napp/assets/stylesheets/*\n")
      write(sources_path, "/* tracked while effectively ignored by a broad glob */\n")
      system("git", "-C", destination, "init", "-q")
      system("git", "-C", destination, "add", "-f", sources_path)

      output = capture_generator(sync: true)

      expect(output).to include("git rm --cached #{sources_path}")
    end

    it "an explicit negation also silences the git-tracked drift warning (a deliberate commit)" do
      build_skeleton
      write(sources_path, "/* deliberately committed */\n")
      write(".gitignore", "!#{sources_path}\n")
      system("git", "-C", destination, "init", "-q")
      system("git", "-C", destination, "add", sources_path)

      output = capture_generator(sync: true)

      expect(output).not_to include("git rm --cached")
    end

    it "adds the entry on --sync (the fleet-wide upgrade path)" do
      build_skeleton
      write(".gitignore", "/node_modules\n")

      run_generator(sync: true)

      expect(read(".gitignore")).to match(%r{^/#{Regexp.escape(sources_path)}$})
    end

    it "warns to git rm --cached when the file is tracked by git (warn-only, never mutates git)" do
      build_skeleton
      write(sources_path, "/* stale committed copy */\n")
      system("git", "-C", destination, "init", "-q")
      system("git", "-C", destination, "add", sources_path)

      output = capture_generator(sync: true)

      expect(output).to include("git rm --cached #{sources_path}")
      # Warn-only: still tracked, file untouched.
      expect(system("git", "-C", destination, "ls-files", "--error-unmatch", sources_path,
                    out: File::NULL, err: File::NULL)).to be(true)
    end

    it "ignores machine-local excludes (.git/info/exclude) — the sync report is machine-independent" do
      # The drift verdict must come from the repo's COMMITTED .gitignore files
      # only: a developer's personal excludes (.git/info/exclude or a global
      # core.excludesFile) would otherwise flip the warning per machine — and
      # its "the ignore entry is in place" guidance would be a lie (the repo
      # has no entry). Here only info/exclude ignores the tracked file: the
      # report must stay quiet on the tailwind drift.
      build_skeleton
      write(sources_path, "/* tracked; ignored only by a personal exclude */\n")
      system("git", "-C", destination, "init", "-q")
      system("git", "-C", destination, "add", sources_path)
      FileUtils.mkdir_p(File.join(destination, ".git/info"))
      File.write(File.join(destination, ".git/info/exclude"), "#{sources_path}\n")

      report = DocsKit::Generators::SyncReport.new(destination)

      expect(report.items.join).not_to include("git rm --cached")
    end

    it "does NOT warn when the site is not a git repository" do
      build_skeleton
      write(sources_path, "/* generated locally, no repo */\n")

      output = capture_generator(sync: true)

      expect(output).not_to include("git rm --cached")
    end
  end

  # Version-aware sync: the generator records which docs-kit version a site was
  # last synced at (a `# docs-kit synced: vX.Y.Z` stamp in the initializer) so a
  # future `--sync` can run the ORDERED migrations between that version and the
  # gem's current version — not just diff against head. The stamp is inert (a
  # comment), lives in the one file every site has, and is injectable into an
  # existing initializer the generator otherwise never rewrites.
  describe "version stamping (records the last-synced docs-kit version)" do
    let(:stamp) { "# docs-kit synced: v#{DocsKit::VERSION}" }

    it "stamps the current gem version into the initializer on a full install" do
      build_skeleton
      run_generator

      expect(read("config/initializers/docs_kit.rb")).to include(stamp)
    end

    it "injects the stamp into an existing (never-clobbered) initializer that lacks one" do
      # A site created before this feature has an un-stamped initializer the
      # generator must not rewrite. --sync injects the stamp comment without
      # touching the site's config body.
      build_skeleton
      write("config/initializers/docs_kit.rb", <<~RUBY)
        # frozen_string_literal: true
        DocsKit.configure do |c|
          c.brand = "My Hand-Edited Brand"
        end
      RUBY

      run_generator(sync: true)

      initializer = read("config/initializers/docs_kit.rb")
      expect(initializer).to include(stamp)
      # The site's edited config body is preserved.
      expect(initializer).to include(%(c.brand = "My Hand-Edited Brand"))
    end

    it "updates a stale stamp to the current version on --sync (never duplicates it)" do
      build_skeleton
      write("config/initializers/docs_kit.rb", <<~RUBY)
        # docs-kit synced: v0.9.0
        # frozen_string_literal: true
        DocsKit.configure { |c| c.brand = "X" }
      RUBY

      run_generator(sync: true)

      initializer = read("config/initializers/docs_kit.rb")
      expect(initializer).to include(stamp)
      expect(initializer).not_to include("v0.9.0")
      expect(initializer.scan("docs-kit synced:").size).to eq(1)
    end

    it "is idempotent — a second run leaves exactly one current stamp" do
      build_skeleton
      run_generator
      run_generator(sync: true)

      initializer = read("config/initializers/docs_kit.rb")
      expect(initializer.scan("docs-kit synced:").size).to eq(1)
      expect(initializer).to include(stamp)
    end
  end

  # The payoff of the stamp: --sync computes the gap between the site's
  # last-synced version and the gem's version and runs the ordered migrations
  # in between, printing warn-only messages for anything a migration can't
  # safely automate (the #24 drift pattern). The default registry ships EMPTY at
  # 1.0.x, so these assert the WIRING (the gap is read, the registry is invoked,
  # warnings surface) against an injected registry rather than a real transform.
  describe "version-aware migrations (--sync runs ordered transforms across the gap)" do
    # A registry whose one migration records that it ran (by writing a marker
    # file into the site) and emits a warning — so we can assert the generator
    # read the stamp, invoked the registry, and printed the warning. `to`
    # defaults to the installed gem version (a migration introduced in THIS
    # release): the realistic case, and within the registry's `upto` ceiling so
    # it's applicable to a site stamped below it. A `to` above DocsKit::VERSION
    # would be filtered as unreleased.
    def stub_default_registry(to: DocsKit::VERSION, warnings: ["do the manual thing the migration can't automate"])
      migration = DocsKit::Generators::Migration.new(to: to, description: "a migration") do |root, _gen|
        File.write(File.join(root, ".migration-ran"), "yes")
        warnings
      end
      registry = DocsKit::Generators::MigrationRegistry.new([migration])
      allow(DocsKit::Generators::MigrationRegistry).to receive(:default).and_return(registry)
    end

    it "runs applicable migrations for a stamped site and prints their warnings" do
      build_skeleton
      run_generator # full install → stamps the current version
      # Roll the stamp back so the stubbed migration (at the gem version) is applicable.
      write("config/initializers/docs_kit.rb",
            "# docs-kit synced: v0.9.0\n#{read('config/initializers/docs_kit.rb')}")
      stub_default_registry

      generator = described_class.new([], { sync: true }, destination_root: destination)
      output = capture_stream { generator.invoke_all }

      expect(exist?(".migration-ran")).to be(true)
      expect(output).to include("do the manual thing the migration can't automate")
    end

    it "runs no migrations when the site is already at the current version" do
      build_skeleton
      run_generator # stamps current version
      # A migration AT the current version has already been applied at that sync.
      stub_default_registry(to: DocsKit::VERSION, warnings: [])

      generator = described_class.new([], { sync: true }, destination_root: destination)
      capture_stream { generator.invoke_all }

      expect(exist?(".migration-ran")).to be(false)
    end

    it "treats a pre-feature (un-stamped) site as earliest (runs every migration)" do
      build_skeleton
      # A site created before the stamp landed: it HAS an initializer, but with
      # no synced-version stamp. create_initializer never clobbers it, so it
      # survives into run_migrations, which reads it as 0.0.0 (earliest) — every
      # migration up to the gem version applies.
      write("config/initializers/docs_kit.rb", <<~RUBY)
        # frozen_string_literal: true
        DocsKit.configure { |c| c.brand = "Legacy Site" }
      RUBY
      stub_default_registry

      generator = described_class.new([], { sync: true }, destination_root: destination)
      capture_stream { generator.invoke_all }

      expect(exist?(".migration-ran")).to be(true)
    end

    it "does not run migrations on a full (non-sync) install" do
      build_skeleton
      stub_default_registry

      generator = described_class.new([], {}, destination_root: destination)
      capture_stream { generator.invoke_all }

      # A full install is a fresh scaffold, not an upgrade — nothing to migrate.
      expect(exist?(".migration-ran")).to be(false)
    end
  end
end
