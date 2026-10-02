---
description: "Executes full autonomous engineering workflow with verification. Use when implementing complete features, tackling GitHub issues, or running end-to-end development cycles."
model: opus
argument-hint: "GitHub issue number/URL or feature description"
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr create:*), Bash(gh pr edit:*), Bash(gh pr view:*), Bash(bin/labels:*), Bash(bundle exec:*), Bash(bun:*), Bash(git:*), Read, Write, Edit, Glob, Grep, Agent
---

# LFG - Full Autonomous Workflow

Execute a complete engineering workflow with verification at each phase.

## Phase 0: Branch Setup

**BEFORE any other work, prepare the git branch:**

1. Check the current branch: `git branch --show-current`
2. If NOT on `main`, switch: `git checkout main`
3. Pull latest: `git pull origin main`
4. Create feature branch: `git checkout -b issue-{number}-{brief-description}` (or `feature/{description}` if no issue number)

---

## Phase 1: Understand

### Step 1: Gather Requirements

If `$ARGUMENTS` is a GitHub issue number or URL:

```bash
gh issue view <number> --json title,body,labels,assignees,comments
```

If `$ARGUMENTS` is a description, use it directly.

**Keep the issue's `type` and `area` labels** — Phase 7 puts them on the pull request. `/lfg` never edits the issue's own labels; the issue's lifecycle is the user's to manage. If the issue has none, or you were given a description instead of an issue, infer them: one `type` label plus `bin/labels infer <changed paths>` for the areas (`.github/LABELS.md`).

### Step 2: Define Acceptance Criteria

**MANDATORY:** Write explicit acceptance criteria:

- **GIVEN** [context/setup]
- **WHEN** [action taken]
- **THEN** [expected outcome]

You MUST NOT proceed until you can articulate these clearly.

### Step 3: Comprehension Gate

Before proceeding, you must:

1. State the problem/feature in one sentence
2. Explain WHY this is needed (the user-facing payoff — docs sites that look identical, maintained in one place)
3. List what changes from the consuming site's perspective (the config/component/generator API delta)
4. Identify edge cases not explicitly mentioned
5. Explain the flow: `DocsKit.configure` → the `DocsUI::` component reads config → Phlex renders through a real view context → the CSS build scans the Ruby → the browser gets the chrome. Which link changes?

If you cannot complete ALL five items, investigate further.

### Step 4: Create Task List

Create a TaskCreate todo list with specific implementation steps.

---

## Phase 2: Explore

1. Find related files (Glob/Grep or Explore agent)
2. Read existing patterns in similar components
3. Understand integration points across the layers
4. Check existing test coverage in `spec/`
5. Review the component kit in `app/components/docs_ui/` (Shell, Sidebar, Code, Page, ThemeSwitcher, …)
6. Review the config surface in `lib/docs_kit/configuration.rb` (any new knob a site must set goes here)
7. Review the registry mixin + value object (`lib/docs_kit/registry.rb`, `lib/docs_kit/nav_item.rb`)
8. Review the engine (`lib/docs_kit/engine.rb`) — it auto-pins the `docs-nav` controller and mounts assets
9. Review the install generator (`lib/generators/docs_kit/install/`) — a new required setup step must land in the templates/`docs-kit new` template
10. Review the one client controller (`app/javascript/docs_kit/controllers/docs_nav_controller.js`) — collapse persistence + auto-TOC

---

## Phase 3: Plan

1. List files to modify with specific changes
2. List new files to create with purpose
3. Identify the config default vs. per-site override (a new behavior host apps tune goes on `Configuration`)
4. Plan test coverage across layers (TDD: tests FIRST) — config, component render, registry, generator
5. Update the task list
6. Consider backwards compatibility (existing consuming sites must keep working verbatim)
7. If the change adds classes the CSS must generate, plan the `@source` / `@source inline(...)` update (Tailwind scans Ruby, and Drawer classes are render-time)

---

## Phase 4: Implement (TDD)

### The deviation log (keep it from the first edit)

The plan is the map; the codebase is the territory. The moment reality forces a choice the plan or issue didn't settle, log it in `implementation-notes.md` at the repo root — one line, at the moment it happens, not reconstructed later:

- **Deviations** — the plan said X, you did Y, because Z
- **Discoveries** — facts about the codebase the plan didn't know
- **Judgment calls** — choices the user might have made differently (defaults, naming, scope cuts)

Pick the conservative option and keep going. The log is how the user audits your judgment afterwards. Never commit the file: its contents move into the PR body, then the file is deleted.

For each logical unit:

### 4.1: Write Failing Test First

```bash
bundle exec rspec <spec_file>
```

### 4.2: Implement Minimum Code

Write the MINIMUM code to make the test pass. Follow project patterns:

| Never Do | Always Do |
|----------|-----------|
| Hand-write raw daisyUI markup | Compose from `DocsUI::` Phlex components |
| Hardcode a site-specific value in a component | Read it from `DocsKit.configuration` |
| Require JS for the page to work | Server-render a working page; JS only *enhances* |
| Add a Stimulus controller per feature | The ONE `docs-nav` controller, auto-pinned |
| Offer a theme the CSS never built | Keep `config.themes` in sync with the Tailwind `@plugin` list |
| Fabricate a view context to render | Render through a real view context (CSRF, `dom_id`, url helpers must work) |
| Add a required setup step only to the README | Also wire it into the install generator / `docs-kit new` template |

### 4.3: Refactor

Once green, refactor while keeping tests passing.

### 4.4: Validate

```bash
bundle exec rubocop
```

### 4.5: Repeat

Move to the next unit. Mark task items complete.

---

## Phase 5: Deep Root Cause Analysis (Bug Fixes Only)

**If this is a bug fix, investigate before implementing.**

### Trace the lifecycle

For the failing behavior:
- Did it originate in config, in a component's render, in the CSS build (a class not scanned), or in the `docs-nav` controller?
- Is it a server-render bug or a client-enhancement bug (does it reproduce with JS off)?
- What ASSUMPTIONS does the code make at the failure point? Which was violated, and WHY?

### Use git history

```bash
git log --oneline -20 <file>
git blame <file>
```

### Map all callers

Use Grep to find every call site. Does the bug happen only for a certain config
(no version badge, empty nav group)? Only for a specific theme? Only when a
consuming site overrides a default?

### Five Whys

Keep asking WHY until you reach the real fix point.

### Fix-location principle

The best fix is usually NOT where the error surfaced:
- daisyUI class missing at runtime → the Tailwind `@source` scan, not an inline class hack
- Sidebar collapsed with JS off → server-render sections `open`, not a JS fallback
- Switcher offers a dead theme → sync `config.themes` with the CSS build, not filter in the view
- Active link wrong → the server-side path match, not a client patch

### Unacceptable superficial fixes — DO NOT DO THESE

- `rescue nil` / bare `rescue` to silence an error you don't understand
- `&.` to paper over a nil without finding why it's nil
- `return if x.nil?` to silently skip
- swallowing errors instead of logging + fixing the cause

**These HIDE bugs. Find the EARLIEST point you could prevent the error and fix there.**

---

## Phase 6: Verify

**ALL of these must pass before committing:**

```bash
bundle exec rubocop
bundle exec rspec
# CSS-affecting changes (new emitted classes): rebuild and eyeball the output
bun run build:css   # if the change adds/renames classes the Tailwind build must scan
```

### Solution verification

- "If I were the requester, is this fully resolved?"
- "Did I fix the ROOT CAUSE, not the symptom?"
- "Do the tests prove it?"
- "Does every existing consuming site still work verbatim (backwards compatible)?"
- "If the change needs setup, does the install generator / `docs-kit new` template do it?"

---

## Phase 7: Commit & PR

### Commit

```bash
git add <specific_files>
git commit -m "$(cat <<'EOF'
feat(scope): brief description

## Summary
[What changed and why]

## Test Coverage
- spec 1: validates X
- spec 2: validates the config-driven default

## Verification
- [x] bundle exec rubocop passes
- [x] bundle exec rspec passes
EOF
)"
```

### Push & PR

```bash
git push -u origin $(git branch --show-current)

gh pr create --title "feat(scope): brief description" --label <type> --label <area> --body-file /tmp/pr-body.md
```

**Label the PR — every time.** The `--label` flags are the issue's `type` + `area` labels from Phase 1, never a `status` label (`plan`, `epic`, …). For a description-only run, infer them: one `type` (`.github/LABELS.md` maps conventional-commit prefixes to types) plus `bin/labels infer $(git diff --name-only origin/main...HEAD)`. Exactly one type, at least one area. `gh pr create` fails on a label that doesn't exist on GitHub: run `bin/labels sync` (or label after the fact with `gh pr edit <n> --add-label …`).

Write the PR body to a temp file (`--body-file`) to avoid shell-interpolation of
backticks/tables. The body is copied verbatim — if you would not type a
backslash in a GitHub comment, do not type one in the heredoc.

The PR body MUST end with a `## Deviations & judgment calls` section copied from
`implementation-notes.md` (then delete the file). If the plan held completely,
write "None — the plan held." This section is read FIRST in review — it is the
audit trail for every decision the plan didn't make.

---

## Phase 8: Comprehension Close-Out

The tests prove the CODE is right; this phase keeps the USER's mental model right. After the PR is up, end your final message with:

1. **The decisions, not the diff** — the 3–5 non-obvious choices in this change someone must understand to maintain it. Lead with anything from the deviation log; the user has never seen those.
2. **Three merge-gate questions** the user should be able to answer before merging. If any answer isn't obvious to them, offer a walkthrough — an unanswerable question is comprehension debt, and merging anyway is how it compounds.

---

## Verification Checklist

- [ ] All acceptance criteria met
- [ ] Tests written BEFORE implementation
- [ ] `bundle exec rubocop` passes
- [ ] `bundle exec rspec` passes
- [ ] Backwards compatible — existing consuming sites unchanged
- [ ] New setup wired into the install generator / `docs-kit new` template
- [ ] CSS build scans any new emitted classes (`@source` updated if needed)
- [ ] PR created with summary + test plan
- [ ] PR labelled: one `type` + at least one `area`, no `status` (`.github/LABELS.md`)
- [ ] PR body ends with `## Deviations & judgment calls` (from implementation-notes.md, since deleted)
- [ ] Comprehension close-out delivered (decisions + three merge-gate questions)

Now, execute this workflow for the provided issue or feature.
