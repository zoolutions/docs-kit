---
description: Review a GitHub pull request for code quality, patterns, and best practices
model: opus
argument-hint: "PR URL or number (e.g., 5 or https://github.com/zoolutions/docs-kit/pull/5)"
---

# PR Review

Review a PR for pattern compliance and issues. Be concise.

## Workflow

1. Fetch PR details and diff via `mcp__github__pull_request_read`
2. Categorize files by layer (config, registry, components, controller, engine, generator, deploy, docs)
3. Check for pattern violations
4. Output a structured review

## Pattern Violations to Check

```text
# WRONG -> RIGHT
Raw daisyUI markup in a view          -> Compose from DocsUI:: Phlex components
Hardcoded site value in a component   -> Read from DocsKit.configuration
Page requires JS to work              -> Server-render working; JS enhances (progressive)
New per-feature Stimulus controller   -> Extend the ONE docs-nav controller
Theme in config not in the CSS build  -> Keep config.themes in sync with @plugin themes
New emitted class, no CSS scan         -> Update @source / @source inline(...)
raw()/html_safe on config free text   -> Let Phlex escape text
Render page to a bare string          -> #render_page through a real view context
Required setup in README only         -> Also wire the install generator + docs-kit new
Manual gem push                       -> rake release[X.Y.Z]
```

## Output Format

```
## Files Requiring Manual Review

| File | Reason |
|------|--------|
| app/components/docs_ui/sidebar.rb | Active-nav server render + config-driven groups |
| lib/docs_kit/configuration.rb | New knob — verify default + backwards compat |
| lib/generators/docs_kit/install/... | Generated setup — verify new sites get the feature |

## Critical Issues

- `app/components/docs_ui/code.rb:NN` - Filename inserted without escaping
- `lib/docs_kit/configuration.rb:NN` - New required knob has no default (breaks existing sites)

## Suggestions (non-blocking)

- Consider extracting X

## Verdict

**Request Changes** | **Approve** | **Comment** — one-line justification
```

## Tools

```text
mcp__github__pull_request_read
  method: "get"        -> PR details
  method: "get_diff"   -> Changes
  method: "get_files"  -> File list
  method: "get_status" -> CI status

bundle exec rubocop      -> Style checks
bundle exec rspec        -> Tests
```
