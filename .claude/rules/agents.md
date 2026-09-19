# Agent Orchestration Rules

## Available Agents

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| Explore | Codebase exploration | Finding files, understanding patterns across the gem + generators |
| Plan | Implementation planning | Complex features spanning component → config → generator |
| general-purpose | Multi-step tasks | Research, complex searches |

## Immediate Agent Usage

Use agents PROACTIVELY without waiting for a prompt:

1. **Complex feature requests** → Plan agent first
2. **Codebase exploration** → Explore agent
3. **Multi-file searches** → Explore agent (not direct Glob/Grep)
4. **Cross-repo questions** (docs-kit ↔ a consuming docs site) → Explore agent against both checkouts

## Model tiers for subagents

When spawning subagents for **mechanical** work (file finding, pattern scans,
naming-convention sweeps), pass a cheaper model explicitly (`model: haiku`)
rather than letting them inherit the session model. Use `model: sonnet` when a
subsystem must be read and summarized. Keep the expensive model for judgment in
the main session. See `.claude/README.md` for the tier convention.

## Parallel Execution

ALWAYS run independent operations in parallel:

```markdown
# GOOD: parallel
1. Agent 1: how DocsUI::Sidebar builds config-driven nav today
2. Agent 2: how the docs-nav Stimulus controller reads headings for the auto-TOC
3. Agent 3: what the install generator scaffolds

# BAD: sequential when independent
```

## When to Use Explore

Use the Explore agent (subagent_type=Explore) instead of direct Glob/Grep when:
- Open-ended exploration across the gem (`lib/`, `app/`, `lib/generators/`)
- Confirming how a consuming docs site wires docs-kit (config, Tailwind
  `@source`, importmap, deploy) before changing the install generator or the
  reusable workflow — verify the real integration, don't assume.
