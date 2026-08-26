# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class Deploy < DocsUI::Page
        title "Deploy"
        eyebrow "Reference"

        def lead = "One reusable workflow deploys every docs-kit site to dash + GHCR."

        def content
          DocsUI::Section("Scaffolded for you") do
            prose do
              p do
                plain "The CLI writes the whole deploy: "
                code { "config/deploy.yml" }
                plain ", "
                code { ".dash/secrets" }
                plain ", a "
                code { "Dockerfile" }
                plain ", and a "
                code { ".github/workflows/deploy-docs.yml" }
                plain " that calls the shared reusable workflow. Point it at your repo and you have a deployable app:"
              end
            end
            DocsUI::Code(<<~SHELL, lexer: :shell)
              docs-kit new my-docs --image OWNER/REPO --service my-repo
            SHELL
          end

          DocsUI::Section("The Docker image", description: "Lean, multi-stage, and upgradable.") do
            prose do
              p do
                plain "The scaffolded "
                code { "Dockerfile" }
                plain " is a multi-stage build: a throwaway "
                code { "build" }
                plain " stage carries the toolchain (build-essential, git, bun) and compiles the gems + assets, and the final stage copies "
                strong { "only" }
                plain " the installed bundle and the app — no compilers, no "
                code { "node_modules" }
                plain ". A shipped "
                code { ".dockerignore" }
                plain " keeps the build context small (no "
                code { ".git" }
                plain ", "
                code { "node_modules" }
                plain ", logs, specs, or coverage). When the site bundles "
                code { "thruster" }
                plain " (a Rails 8 default), "
                code { "bin/thrust" }
                plain " fronts Puma with HTTP caching, compression, and X-Sendfile — Thruster listens on the routed port (3000) and proxies to Puma."
              end
              p do
                plain "The "
                code { ".dockerignore" }
                plain " is gem-owned — every "
                code { "docs_kit:install" }
                plain " run refreshes it. The "
                code { "Dockerfile" }
                plain " is yours to tune, so the generator never clobbers it; it stamps a version marker ("
                code { "# docs-kit Dockerfile vX.Y.Z" }
                plain ") so "
                code { "--sync" }
                plain " warns you when a newer, leaner template ships. Diff and adopt:"
              end
            end
            DocsUI::Code(<<~SHELL, lexer: :shell)
              bin/rails g docs_kit:install --sync   # warns if your Dockerfile is stale
              diff Dockerfile "$(bundle show docs-kit)/lib/generators/docs_kit/install/templates/Dockerfile.tt"
            SHELL
          end

          DocsUI::Section("The reusable workflow") do
            prose do
              p do
                plain "Build and deploy live "
                strong { "once" }
                plain " in "
                code { "zoolutions/docs-kit/.github/workflows/deploy.yml" }
                plain ". Each site's "
                code { ".github/workflows/deploy-docs.yml" }
                plain " is a thin caller — no build logic is copied per site."
              end
            end
            DocsUI::Code(<<~YAML, lexer: :yaml, filename: ".github/workflows/deploy-docs.yml")
              on:
                release: { types: [published] }
                workflow_dispatch:

              permissions:
                contents: read
                packages: write

              jobs:
                deploy:
                  uses: zoolutions/docs-kit/.github/workflows/deploy.yml@main
                  with:
                    image: OWNER/REPO
                    service: my-repo
                  secrets: inherit
            YAML
          end

          DocsUI::Section("Naming", description: "Use the repo name.") do
            prose do
              p do
                plain "Set "
                code { "image" }
                plain " and "
                code { "service" }
                plain " to the repo's "
                code { "OWNER/REPO" }
                plain ". The pushed GHCR package then auto-links to the repo, so "
                code { "GITHUB_TOKEN" }
                plain " can push "
                strong { "and" }
                plain " pull it — no PAT required."
              end
            end
            DocsUI::Callout(:warning) do
              plain "A name that doesn't match the repo becomes an unlinked package that "
              code { "GITHUB_TOKEN" }
              plain " can't pull — the deploy fails when dash tries to fetch the image."
            end
          end

          DocsUI::Section("Secrets") do
            render DocsUI::PropTable.new(
              [
                [ "SSH_PRIVATE_KEY", "Deploy key for the dash SSH user." ],
                [ "DEPLOY_HOST", "The deploy host (IP or DNS)." ],
                [ "DEPLOY_DOMAIN", "The public host dash-proxy routes." ]
              ],
              headers: [ "Secret", "Purpose" ]
            )
            prose do
              p do
                plain "Add these to a "
                code { "docs" }
                plain " GitHub Environment. The registry password is the auto-provided "
                code { "GITHUB_TOKEN" }
                plain ", so "
                code { "secrets: inherit" }
                plain " passes everything the reusable workflow needs."
              end
            end
          end

          DocsUI::Section("Requirements the caller must set") do
            DocsUI::Callout(:warning) do
              plain "The caller workflow MUST grant "
              code { "permissions: packages: write" }
              plain " itself — a reusable workflow can't escalate its caller's permissions. Without it the deploy fails at startup, before any dash step runs."
            end
          end
        end
      end
    end
  end
end
