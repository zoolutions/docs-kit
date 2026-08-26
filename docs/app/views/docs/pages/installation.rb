# frozen_string_literal: true

module Views
  module Docs
    module Pages
      # How to install docs-kit: scaffold a new site, add it to an existing app,
      # and re-run the generator with --sync to pull new wiring on upgrade.
      class Installation < DocsUI::Page
        title "Installation"
        eyebrow "Getting started"

        def lead = "Scaffold a new docs site in one command, add docs-kit to an existing Rails app, or re-run the generator with --sync to upgrade."

        def content
          new_site_section
          existing_app_section
          upgrade_section
          requirements_section
          verify_section
        end

        private

        def new_site_section
          DocsUI::Section("New site in one command", description: "The fastest path — a deployable app from scratch.") do
            DocsUI::Code(<<~SHELL, lexer: :shell)
              docs-kit new my-docs --image OWNER/REPO --service my-repo
            SHELL
            md <<~'MD'
              This runs `rails new` (propshaft + importmap + turbo/stimulus, no
              database) and applies the docs-kit template, which:

              - adds the gem and its dependencies,
              - runs the install generator,
              - syncs the lucide icons,
              - builds the Tailwind CSS, and
              - scaffolds the dash deploy.

              Then boot it:
            MD
            DocsUI::Code(<<~SHELL, lexer: :shell)
              cd my-docs && bin/dev
            SHELL
            DocsUI::Callout(:tip) do
              plain "The generator path (docs-kit new) performs every step in the "
              plain "“Add to an existing Rails app” section below automatically. Reach for the manual steps only when adding docs-kit to an app you already have."
            end
          end
        end

        def existing_app_section
          DocsUI::Section("Add to an existing Rails app",
                          description: "Four steps: the gems, the generator, the icons, the CSS.") do
            existing_app_gemfile
            existing_app_generator
            existing_app_manifest
            existing_app_icons
            existing_app_css
          end
        end

        def existing_app_gemfile
          md "**1. Add the gems.**"
          DocsUI::Code(<<~RUBY, filename: "Gemfile")
            gem "docs-kit"
            gem "daisyui", require: "daisy_ui"
            gem "phlex-rails"
            gem "rails_icons", "~> 1.1"
            gem "rouge"
          RUBY
          md "Then run `bundle install`."
        end

        def existing_app_generator
          md "**2. Run the install generator.**"
          DocsUI::Code(<<~SHELL, lexer: :shell)
            rails g docs_kit:install
          SHELL
          md <<~'MD'
            It is fully idempotent — safe on a fresh app AND a years-old site, so
            re-running it is the sanctioned [upgrade path](#upgrade-an-existing-site).
            File creations skip what already exists; the config initializer is
            never clobbered; routes are skipped even when the site wrote them in
            its own style.
          MD
        end

        def existing_app_manifest
          md "The generator wires the following into your app:"
          render DocsUI::PropTable.new(
            [
              [ "config/initializers/docs_kit.rb", "The site config — brand, themes, nav. Skipped if present (never clobbered)." ],
              [ "config/initializers/phlex.rb", "Phlex autoload namespaces (Views::, Components::)." ],
              [ "config/initializers/rails_icons.rb", "The rails_icons config for the lucide chrome icons." ],
              [ "app/models/doc.rb", "The Doc registry, seeded with a sample page." ],
              [ "app/views/docs/pages/installation.rb", "A sample page to prove the render path." ],
              [ "routes", "docs/:doc(.:format), the search / llms.txt / llms-full.txt routes, and a commented MCP route." ],
              [ "bin/build-css + application.tailwind.css", "The Bun/Tailwind CSS build, carrying the theme @plugin block." ],
              [ "controllers/index.js", "Registers the docs-nav Stimulus controller (eager-loaded)." ],
              [ "AGENTS.md + .claude skill", "The AI-authoring contract and a write-docs-page Claude Code skill." ],
              [ ".rubocop.yml", "docs-kit's shipped cops, merged into an existing config." ]
            ],
            headers: [ "What", "Why" ]
          )
          DocsUI::Callout(:note) do
            plain "The generator also injects "
            code { "include DocsKit::Controller" }
            plain " into your "
            code { "ApplicationController" }
            plain " — that is what provides the "
            code { "#render_page" }
            plain " helper the docs controller calls."
          end
        end

        def existing_app_icons
          md "**3. Sync the icons.**"
          DocsUI::Code(<<~SHELL, lexer: :shell)
            rails g rails_icons:sync --library=lucide
          SHELL
        end

        def existing_app_css
          md "**4. Build the CSS.**"
          DocsUI::Code(<<~SHELL, lexer: :shell)
            bun install && bun run build:css
          SHELL
          md <<~'MD'
            Then set your brand, themes, and nav in
            `config/initializers/docs_kit.rb` — see
            [Configuration](/docs/configuration) for every knob — and write your
            first page (see [Authoring pages](/docs/authoring)).
          MD
        end

        def upgrade_section
          DocsUI::Section("Upgrade an existing site",
                          id: "upgrade-an-existing-site",
                          description: "rails g docs_kit:install --sync pulls new wiring without touching your content.") do
            md <<~'MD'
              docs-kit ships new wiring over time — new routes, a new Stimulus
              registration, updated AGENTS.md guidance, RuboCop cops. To pull
              those into an existing site, re-run the generator with `--sync`.
              This is the **sanctioned upgrade path**.
            MD
            DocsUI::Code(<<~SHELL, lexer: :shell)
              rails g docs_kit:install --sync
            SHELL
            md <<~'MD'
              `--sync` is *additive*. It runs ONLY the idempotent wiring steps and
              scaffolds no content:

              - **Runs** the routes, the initializer hint, the importmap/Stimulus
                registration, the AGENTS.md block, and the `.rubocop.yml` cops.
              - **Skips** everything you own — the `Doc` registry, your pages, and
                the `application.tailwind.css` build. Those already exist and are
                yours to edit, so a sync never touches them.
            MD
            upgrade_drift
            DocsUI::Callout(:tip) do
              plain "After a sync: run "
              code { "bun run build:css" }
              plain " to pick up any new emitted classes, then "
              code { "bundle exec rspec" }
              plain " to confirm the site still boots and renders."
            end
          end
        end

        def upgrade_drift
          md <<~'MD'
            A sync also prints a **drift report** — manual cleanup it detects but
            won't do for you, because it can't safely automate a delete. It warns,
            never deletes, and never fails the run. The two items it looks for:
          MD
          render DocsUI::PropTable.new(
            [
              [ "A hand-rolled render_page", "app/controllers/application_controller.rb defines its own #render_page — DocsKit::Controller already provides it, so the copy shadows the gem's. Delete it." ],
              [ "A dead IconHelper", "app/helpers/icon_helper.rb is dead code — docs-kit renders icons via rails_icons (DocsUI::Icon). Delete it." ]
            ],
            headers: [ "Drift", "What to do" ]
          )
        end

        def requirements_section
          DocsUI::Section("Requirements") do
            render DocsUI::PropTable.new(
              [
                [ "Ruby", ">= 3.2" ],
                [ "Rails", ">= 7.1" ],
                [ "Bun", "for the Tailwind CSS build" ],
                [ "PostgreSQL", "not required (docs sites are stateless)" ]
              ],
              headers: [ "Requirement", "Version/Note" ]
            )
          end
        end

        # Kept as a Prose() block (not md) on purpose: this page mixes both
        # authoring styles to prove Prose stays fully supported alongside md.
        def verify_section
          DocsUI::Section("Verify") do
            prose do
              p do
                plain "Boot the app with "
                code { "bin/dev" }
                plain " and visit "
                code { "/docs" }
                plain ". You should see the shell with the sidebar, the theme switcher, and this page's content."
              end
            end
          end
        end
      end
    end
  end
end
