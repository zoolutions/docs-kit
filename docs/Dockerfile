# syntax = docker/dockerfile:1
#
# docs-kit's own docs site dogfoods the gem via `gem "docs-kit", path: ".."`, so
# the build context is the REPO ROOT (gem at /app, docs app at /app/docs). Build
# from the repo root: the reusable workflow uses context "." + dockerfile
# "docs/Dockerfile". The repo-root .dockerignore keeps that context small.
#
# Multi-stage: the throwaway `build` stage carries the toolchain (build-essential,
# git, bun) and compiles gems + assets; the final stage copies only the installed
# bundle + the app, so none of the build tooling ships in the runtime image.

ARG RUBY_VERSION=3.4.2
FROM ruby:$RUBY_VERSION-slim AS base

ARG BUN_VERSION=1.3.2
ENV BUN_INSTALL="/usr/local/bun"
ENV PATH="/usr/local/bun/bin:$PATH"

WORKDIR /app/docs

ENV BUNDLE_DEPLOYMENT="0" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_GEMFILE="/app/docs/Gemfile" \
    RAILS_ENV="production"

# Runtime-only packages (jemalloc for a leaner heap, curl for the healthcheck).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
RUN gem update --system --no-document && gem install -N bundler


# --- Build stage (throwaway) --------------------------------------------------
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config unzip
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"

# The whole repo (gem at /app, app at /app/docs). The path gem's gemspec packages
# its files via `git ls-files`, falling back to a Dir[] glob when .git is absent
# (the .dockerignore drops .git) — so bundle install still sees the full manifest.
COPY . /app/

# Install gems, then prune the bundler cache + any git-sourced gem checkouts so
# they don't bloat the layer the final stage copies.
RUN bundle config set frozen false && bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

RUN bun install --frozen-lockfile
# assets:precompile runs bun run build:css via the css:build rake enhance. Drop
# node_modules + the bun/asset caches afterwards — only the built CSS is kept, so
# the final stage's COPY of /app never carries the 39 MB of JS deps.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules /usr/local/bun tmp/cache


# --- Final stage --------------------------------------------------------------
FROM base

# dash verifies this label on the --skip-push deploy; must equal `service:` in
# config/deploy.yml (= the repo name, docs-kit).
LABEL service="docs-kit"

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /app /app

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R 1000:1000 /app/docs/log /app/docs/tmp
USER 1000:1000

EXPOSE 3000
# Thruster fronts Puma (HTTP caching + compression + X-Sendfile). It listens on
# HTTP_PORT and proxies to Puma on TARGET_PORT (it sets PORT for the child, which
# config/puma.rb reads). HTTP_PORT MUST be the port traffic is routed to (dash's
# `app_port: 3000` in config/deploy.yml, the EXPOSE above) — Thruster's default
# is 80, which the non-root user can't reliably bind AND which dash-proxy would
# never route to, silently bypassing Thruster straight into Puma.
ENV HTTP_PORT="3000" \
    TARGET_PORT="3001"
CMD ["./bin/thrust", "./bin/rails", "server"]
