# The zoolutions release kit

Every zoolutions gem releases the same way: `bin/release` → `rake release[X.Y.Z]`
→ GitHub Release → `release.yml` → RubyGems over OIDC trusted publishing with a
Sigstore attestation. docs-kit holds the canonical copy of the kit;
`script/release-kit` copies it into the other gems and checks them for drift.

| File | Shared how | What it does |
|---|---|---|
| `bin/release` | verbatim | Picks the next version, shows what ships, guards (clean, up-to-date `main`, no downstream pin blocks it), confirms, runs the rake task |
| `rakelib/release.rake` | verbatim | Bumps `version.rb` + the gem's pin in every tracked lockfile (in place, no re-resolve), builds, commits, pushes, creates the GitHub Release |
| `.github/workflows/release.yml` | all but the `test` job | Tests, builds, checksums, signs, publishes, uploads the release assets |

Everything project-specific is derived from the repo's one `*.gemspec` (gem name,
version, `lib/**/version.rb`) or lives in the repo's own `Rakefile` hooks and
`test` job. A consuming repo never edits the kit files in place.

## Gems on the kit

docs-kit (canonical), daisyui, dash, glyphs, importmap-plus, locallingo,
pgbus, phlex-forms, phlex-reactive, sidekiq-unique-jobs, stationery.

## Releasing

```bash
bin/release list           # last releases + what patch/minor/major would give
bin/release --dry-run      # version, changes since the last tag, downstream blockers
bin/release                # patch; `minor`, `major` or an explicit 1.3.0.rc1
bin/release 1.2.0 --force  # delete + re-create an existing tag/release
```

## Hooks

Define these in the repo's `Rakefile` only when the repo needs them. Both receive
the new version.

```ruby
namespace :release do
  # Runs first, before anything is touched. Abort to stop the release.
  task :preflight, [:version] do |_t, args|
    # dash: the proxy image for MINIMUM_VERSION must already be pullable
  end

  # Runs after version.rb is bumped. Rewrite any other TRACKED file that ships
  # with the version; every modified tracked file is committed with the bump.
  task :prepare, [:version] do |_t, args|
    # daisyui: stamp lib/daisy_ui/updated_at.rb
  end
end
```

## The `test` job

The only part of `release.yml` a repo owns. Keep the repo's own matrix and suite,
but always:

- pin actions by SHA and check out with `persist-credentials: false`
- no `bundler-cache` (cache poisoning in a publishing workflow)
- install **frozen** when a `Gemfile.lock` is committed. This is the gate that
  fails a release whose lockfile pins `rake release` missed:

```yaml
      - run: bundle install
        env:
          BUNDLE_FROZEN: ${{ hashFiles('Gemfile.lock') != '' }}
```

`script/release-kit check` fails a repo whose test job lacks that line.

## Adopting the kit in a gem

Automated: from a docs-kit checkout, run `/release-kit ../the-gem` in Claude Code
(`.claude/commands/release-kit.md`). By hand:

1. Branch from a fresh `main`, then `script/release-kit sync ../the-gem`.
2. `release.yml`: the first sync writes the canonical file. Port the repo's own
   test commands, matrix and services into its `test` job (rules above).
3. `Rakefile`: delete the old `task :release` and its helpers. Move any step only
   this gem needs into a `release:preflight` / `release:prepare` hook. If
   `RuboCop::RakeTask` lists explicit patterns, add `rakelib`.
4. RuboCop: `bundle exec rubocop rakelib/release.rake` must pass. If the repo
   enforces a style the shared file can't use (it must stay Ruby 3.2-compatible,
   so no `it`), exclude `rakelib/release.rake` from that one cop.
5. Point the docs (README, AGENTS/CLAUDE.md, `.claude/`) at `bin/release`.
6. Verify: the suite, `bin/release --dry-run`, `bundle exec rake -T | grep release`,
   `zizmor .github/workflows/release.yml`, `script/release-kit check ../the-gem`.
   If the repo runs actionlint, declare `ubuntu-26.04` in `.github/actionlint.yaml`.
7. Open the PR and add the gem to the list above.

## Upgrading the kit

1. Change the kit in docs-kit only (`bin/release`, `rakelib/release.rake`, the
   shared part of `release.yml`) with specs in `spec/rakelib/` and
   `spec/release_kit/`, and merge it.
2. From docs-kit `main`: `script/release-kit sync ../gem-a ../gem-b ...`. It
   rewrites the verbatim files and the shared workflow sections and keeps each
   repo's `test` job.
3. In each gem: branch, verify (step 6 above), open a PR. `/release-kit ../gem`
   does this per repo.
4. `script/release-kit check ../*/` shows who is still behind.
