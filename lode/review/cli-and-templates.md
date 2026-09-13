# Review rules — the `docs-kit new` CLI and the site templates

Accepted review findings about the scaffolding path, rewritten as rules about the system and verified against the code as it is.

### The `docs-kit new` CLI resolves every `DOCS_KIT_*` value before the template runs, so a template default is dead on the CLI path

- **Holds because:** `exe/docs-kit` builds the whole env hash — `DOCS_KIT_GEM_SOURCE`, `DOCS_KIT_IMAGE`, `DOCS_KIT_SERVICE` — and passes it to `system(env, *rails_new)` (`exe/docs-kit:59-63, 80`). `DOCS_KIT_IMAGE` is `opts[:image] || "zoolutions/#{name}"`, so it is always set. `lib/docs_kit/templates/new_site.rb:26` then reads `ENV.fetch("DOCS_KIT_IMAGE", "zoolutions/#{app_name}")` and the fallback never fires — it is reachable only when the template is applied directly (`rails new -m …` by hand). Changing the template's fallback alone therefore fixes nothing a user of the documented command sees, which is exactly what happened when the repo moved from `mhenrixon/` to `zoolutions/`.
- **Where:** `exe/docs-kit:59-63` (the env hash) and `:28` (the `--image` help text) and `:7` (the usage example); `lib/docs_kit/templates/new_site.rb:26`
- **Safe direction:** the three must move together. A CLI default that is wrong is the *unsafe* direction, because the value it scaffolds into `config/deploy.yml` and the caller workflow looks plausible and fails late — an image name that is not the calling repo's `OWNER/REPO` becomes an unlinked user-scoped GHCR package that `GITHUB_TOKEN` cannot pull, so the failure surfaces at deploy time in someone else's repository. Prefer a CLI that errors over one that scaffolds a plausible-but-unlinked name.
- **Proven by:** no test — `exe/docs-kit` has no spec (grepping `spec/` for `DOCS_KIT_IMAGE` or `docs-kit new` returns nothing), and the generator specs exercise `docs_kit:install`, not the CLI. The fallback in `new_site.rb` is likewise unexercised. Treat any edit to either default as untested and check both files plus the two help-text mentions by hand.
- **Origin:** cubic learning ec3d720b; PR #70 review thread (accepted, fixed in `d9adaa2`)
