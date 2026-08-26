# frozen_string_literal: true

require "securerandom"

# Rails application template for a docs-kit docs site. Run via:
#
#   rails new my-docs -a propshaft -j importmap --skip-... -m new_site.rb
#
# (NOT --minimal — that strips JS the shell needs AND the thruster gem the
# generated Dockerfile fronts Puma with; exe/docs-kit passes the right flags.)
#
# or, more simply, via the `docs-kit new` CLI (exe/docs-kit) which supplies the
# right `rails new` flags. It:
#   * adds docs-kit + its runtime deps to the Gemfile,
#   * runs `docs_kit:install` (all the Ruby/CSS/Stimulus wiring),
#   * syncs the lucide icon set and builds the CSS,
#   * scaffolds a deployable dash setup that calls docs-kit's reusable workflow.
#
# The generated app is a complete, deployable standalone docs site.

# --- config the template reads ------------------------------------------------
# DOCS_KIT_GEM_SOURCE lets the dogfood site (docs-kit/docs) depend on the gem via
# path: ".." while a real new site depends on the released gem. Default: rubygems.
gem_source = ENV.fetch("DOCS_KIT_GEM_SOURCE", "") # e.g. 'path: "..", ' or 'github: "zoolutions/docs-kit", '
# The GHCR image/service = the OWNER/REPO the site will live in (repo-linked pkg).
image = ENV.fetch("DOCS_KIT_IMAGE", "zoolutions/#{app_name}")
service = ENV.fetch("DOCS_KIT_SERVICE", app_name)

# --- gems ---------------------------------------------------------------------
gem_line = "gem \"docs-kit\"#{", #{gem_source}" unless gem_source.empty?}"
inject_into_file "Gemfile", after: %r{source ["']https://rubygems\.org["']\n} do
  <<~RUBY

    # docs-kit shared docs chrome + its runtime deps
    #{gem_line}
    gem "daisyui", require: "daisy_ui"
    gem "phlex-rails"
    gem "rails_icons", "~> 1.1"
    gem "rouge"

    # Optional: expose these docs to AI agents over MCP (a read-only /mcp endpoint).
    # Uncomment this and the /mcp route in config/routes.rb. See the docs-kit README.
    # gem "mcp"
  RUBY
end

after_bundle do
  # The whole docs-kit wiring in one call (idempotent).
  generate "docs_kit:install"

  # Sync the lucide icons the chrome renders, then build the CSS.
  run "bin/rails g rails_icons:sync --library=lucide --force --quiet"
  run "bun install --silent" if system("command -v bun >/dev/null 2>&1")
  run "bun run build:css" if system("command -v bun >/dev/null 2>&1")

  # --- deploy scaffolding (dash + the reusable workflow) ---------------------
  create_file "config/deploy.yml", <<~YAML
    # dash deploy → the oss-infrastructure server (Cloudflare Tunnel + dash-proxy).
    # service/image = the repo OWNER/REPO so the ghcr package auto-links to the
    # repo and GITHUB_TOKEN can push + pull it (no PAT). See docs-kit's README.
    service: #{service}
    image: #{image}

    servers:
      web:
        hosts:
          - <%= ENV["DEPLOY_HOST"] %>

    ssh:
      user: <%= ENV.fetch("DEPLOY_SSH_USER", "oss") %>

    proxy:
      host: <%= ENV["DEPLOY_DOMAIN"] %>
      app_port: 3000
      ssl: false
      healthcheck:
        path: /up
        interval: 5
        timeout: 30

    registry:
      server: ghcr.io
      username: mhenrixon
      password:
        - DASH_REGISTRY_PASSWORD

    builder:
      arch: amd64
      context: .
      dockerfile: Dockerfile

    env:
      clear:
        RAILS_SERVE_STATIC_FILES: "true"
        RAILS_LOG_TO_STDOUT: "true"
        # A stateless docs site: SECRET_KEY_BASE only signs cookies, so it's
        # inlined (no user data at risk). Rotate with `bin/rails secret`.
        SECRET_KEY_BASE: "#{SecureRandom.hex(64)}"
  YAML

  create_file ".dash/secrets", <<~SH
    # In CI the deploy workflow sets this to the job's GITHUB_TOKEN. Locally,
    # export it (e.g. DASH_REGISTRY_PASSWORD=$(gh auth token)).
    DASH_REGISTRY_PASSWORD=$DASH_REGISTRY_PASSWORD
  SH

  # The Dockerfile + .dockerignore are written by `docs_kit:install` (run above in
  # after_bundle) so a scaffolded site and an upgrading site share ONE optimized,
  # version-stamped Dockerfile — no divergent copy to maintain here. The generator
  # derives the LABEL service from the app dir basename (= app_name); if the site
  # deploys under a DIFFERENT dash service (`--service`), correct the label to
  # match config/deploy.yml so dash's --skip-push validate_image passes.
  gsub_file "Dockerfile", /LABEL service=".*"/, %(LABEL service="#{service}") if service != app_name

  create_file ".github/workflows/deploy-docs.yml", <<~YAML
    name: Deploy docs
    # Build + deploy via docs-kit's reusable workflow (defined once for all sites).
    on:
      release: { types: [published] }
      workflow_dispatch:
    jobs:
      deploy:
        uses: zoolutions/docs-kit/.github/workflows/deploy.yml@main
        with:
          image: #{image}
          service: #{service}
          build_context: "."
          dockerfile: "Dockerfile"
          working_directory: "."
        secrets: inherit
  YAML

  create_file "Procfile.dev", <<~PROC
    web: bin/rails server
    css: bun run watch:css
  PROC

  say "\n✅ docs-kit docs site scaffolded.", :green
  say <<~MSG
    Next:
      cd #{app_name}
      bin/dev                     # or bin/rails server
      bin/rails docs_kit:og       # generate your social-share image from the landing page
                                  # (needs a headless browser: shot-scraper or chromium)
    SEO: set c.seo.* in config/initializers/docs_kit.rb (description, og_image, twitter_site).
    Deploy: push, create a GitHub Release (or run the Deploy docs workflow).
      Set repo secrets: SSH_PRIVATE_KEY, DEPLOY_HOST, DEPLOY_DOMAIN (env: docs).
  MSG
end
