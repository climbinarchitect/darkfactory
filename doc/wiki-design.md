# darkfactory — Wiki design (long-term memory)

> Status: DESIGN v1. The wiki is the durable, cross-project memory layer: a plain
> markdown+git repo, Obsidian as the human UI, INDEX.md as the agent entrypoint.
> The personal journal is a **separate repo** and is out of scope here by
> construction (dev lines never read it).

## What it is / is not

- **Is**: curated, durable knowledge — decisions with reasons, patterns that
  worked, infra facts, per-project accumulated understanding. The "LLM knowledge
  base" layer (Karpathy): your data as your moat.
- **Is not**: a scratchpad (that's Hermes `MEMORY.md`, ~2,200 chars, volatile by
  design), a task tracker (GitHub issues), a journal (project-journal.md lives in
  the factory repo; personal journal in its own repo), or a docs mirror (project
  docs stay in their repos — the wiki links, never copies).

## Repo layout

```
wiki/
├── INDEX.md                  # map of content — THE entrypoint, human-curated
├── projects/
│   ├── darkfactory.md        # accumulated understanding, links to repo docs
│   └── kaos-fleet-manager.md
├── infra/
│   ├── hetzner-vps.md        # facts: sizing, tailnet names (symbolic), gotchas
│   └── tailscale.md
├── patterns/
│   ├── agent-governance.md   # transferable learnings (bank-relevant, sanitized)
│   └── claude-code-headless.md
└── decisions/
    └── 2026-07-06-hetzner-over-pi.md   # cross-project decisions only;
                                        # project-local decisions stay in project journals
```

## Conventions (binding)

1. **Plain markdown, standard relative links** — `[texte](../infra/tailscale.md)`,
   **never Obsidian `[[wikilinks]]`**. Obsidian reads standard links fine; agents
   and plain-git tooling don't resolve wikilinks. Zero lock-in is the point.
2. **File naming**: kebab-case, no accents, no spaces (same rule as code
   identifiers). Content language: French (comm convention); technical pattern
   notes may be English if reused in English contexts — author's call per file.
3. **Every file starts with a 2–4 line summary block.** An agent (or you) must be
   able to stop after the summary and know whether to read on. This is the
   cheapest token-saver in the design.
4. **Split at ~300 lines.** A file that grows past it becomes a folder + index.
5. **INDEX.md is curated, not generated**: one line per file — path + when to read
   it (same philosophy as the "docs faisant autorité" tables in CLAUDE.md files).
   A file absent from INDEX.md is invisible to agents by protocol.
6. `.obsidian/` is **gitignored** (machine-specific UI state; the vault is just
   the repo root). No required plugins — Obsidian stays optional forever.

## Agent read protocol

- Entry: `INDEX.md`, always. Follow links **at most 2 hops** from the index.
- **Full-repo scans are forbidden by protocol** (registry `context.entrypoints`
  points at INDEX.md only). If an agent can't find it in 2 hops, the index is the
  bug — fix the index, don't widen the search.
- The wiki is read-context for the **orchestrator** (spec drafting, routing).
  Task executors get project-repo context; wiki extracts go into the task spec if
  relevant, curated at plan time — not mounted wholesale into task containers.

## Write protocol (the security decision)

The wiki feeds orchestrator context, which makes it an injection vector if writes
are open. Therefore:

- **v1: humans write, agents propose.** Agent-proposed updates arrive as PRs on
  the wiki repo (or as suggestions on the intake channel); a human merges. The
  wiki's trust level ("curated-trusted") exists *because* writes are gated —
  loosen the gate and the trust level drops with it.
- Distillation flow: Hermes `MEMORY.md` scratchpad accumulates; a periodic
  "wiki gardening" pass (human-triggered, later maybe scheduled) proposes
  promotions of durable facts scratchpad → wiki, as a PR.
- **Write bar** (adopted from omniscient/dark-factory's memory contract): a fact
  is promoted to the wiki only if *a future agent (or you) would make a materially
  different decision because of it, compared to reading the project's CLAUDE.md
  and repo docs alone*. If not → it stays in the scratchpad and dies there. This
  is the gardening pass's acceptance criterion, applied at PR review.
- **Removing a fact has two distinct forms — never conflate them:**
  - **Invalidated**: the claim was never true. Don't delete silently — leave a
    one-line tombstone with the reason (prevents re-adding the same wrong fact).
  - **Superseded**: the claim was true, a newer entry covers it better. Replace,
    and note what supersedes it in the commit message.
  The distinction preserves the "was this ever right?" signal a reader needs when
  weighing historical context.
- No secrets, no tailnet hostnames, no tokens — symbolic names only, same rule as
  the registry.

## INDEX.md skeleton

```markdown
# INDEX — wiki

> Entrée unique. Une ligne par fichier : quoi + quand le lire. Un fichier absent
> d'ici n'existe pas pour les agents.

## Projets
- [darkfactory](projects/darkfactory.md) — compréhension accumulée ; lire avant
  toute session d'orchestration.
- [kaos-fleet-manager](projects/kaos-fleet-manager.md) — contexte cross-session ;
  les faits durables vivent dans le CLAUDE.md du repo, ici les apprentissages.

## Infra
- [hetzner-vps](infra/hetzner-vps.md) — sizing, coûts, gotchas de provisioning.
- [tailscale](infra/tailscale.md) — tailnet, patterns d'accès, SSH.

## Patterns
- [agent-governance](patterns/agent-governance.md) — gates, budget guards,
  leçons transférables.

## Décisions transverses
- [2026-07-06 Hetzner over Pi](decisions/2026-07-06-hetzner-over-pi.md)
```

## Relation to the factory (registry hook)

`_global.yaml` gains an optional pointer once the wiki repo exists:

```yaml
wiki:
  repo: <owner>/wiki
  entrypoint: INDEX.md      # the ONLY file the orchestrator opens unprompted
```

Absent pointer ⇒ factory runs without wiki context (degraded, not broken).

## Non-goals

Vector search / RAG (the index IS the retrieval — revisit only if the index
demonstrably fails at scale), auto-generated indexes, wiki write access for task
executors, hosting the personal journal.
