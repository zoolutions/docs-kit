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

          DocsUI::Section("dash-proxy, switched on", description: "The scaffolded deploy.yml uses the proxy, not just the router.") do
            prose do
              p do
                plain "Every site deploys with "
                a(href: "https://github.com/zoolutions/dash") { "dash" }
                plain " 4 ("
                code { "minimum_version: 4.0.7" }
                plain ") and turns on the per-app dash-proxy features a docs site benefits from — no per-site tuning, the template writes them:"
              end
              ul do
                li do
                  code { "compress: true" }
                  plain " — zstd / brotli / gzip negotiated at the edge; Thruster-encoded responses pass through."
                end
                li do
                  code { "cache: { enabled: true, max_ttl: 300 }" }
                  plain " — an RFC 9111 shared cache. It stores only responses marked "
                  code { "Cache-Control: public" }
                  plain " (Propshaft assets, "
                  code { "/llms.txt" }
                  plain "); HTML carrying a session cookie is refused by design. "
                  code { "dash proxy cache stats" }
                  plain " shows what it holds."
                end
                li do
                  code { "headers" }
                  plain " — "
                  code { "X-Content-Type-Options" }
                  plain " / "
                  code { "Referrer-Policy" }
                  plain " set once at the proxy; "
                  code { "Server" }
                  plain " and "
                  code { "X-Powered-By" }
                  plain " stripped."
                end
                li do
                  code { "intercept_errors: [502, 503, 504]" }
                  plain " + "
                  code { "error_pages_path: public" }
                  plain " — the site's own status pages during a container swap, not a bare \"Bad Gateway\"."
                end
                li do
                  code { "exclude_metrics_paths: [/up]" }
                  plain " — the health probe stays out of the request histograms."
                end
              end
              p do
                plain "Deliberately left alone: "
                code { "proxy.run" }
                plain " is host-wide (every site on the shared host boots the same proxy; a differing "
                code { "run:" }
                plain " block reboots it on each alternate deploy), and "
                code { "rate_limit" }
                plain " / "
                code { "deny_ips" }
                plain " need "
                code { "client_ip.trusted_proxies" }
                plain " pinned to the tunnel's address to key on visitors rather than on cloudflared. "
                code { "dash docs proxy" }
                plain " is the always-current reference."
              end
              p do
                plain "The first dash 4 deploy on a host renames the proxy ("
                code { "kamal-proxy" }
                plain " → "
                code { "dash-proxy" }
                plain ") and copies its config volume — one short outage on that host while ports 80/443 change hands, paid once by whichever site deploys first."
              end
            end
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
              plain " can't pull — the deploy fails when dash tries to fetch the image. Before deploying, the workflow runs "
                code { "dash doctor" }
                plain ", a pre-flight of host, registry, proxy, ports and readiness gates that fails the job early with one report instead of one failure at a time."
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
