# darkfactory — Registry schema

> Status: DESIGN v1. The registry is the governance interface: one directory per
> line, plus one global file. It lives in the **factory repo** (trusted zone) —
> target repos never contain governance (see architecture.md §3, §7).

## Layout

```
registry/
├── _global.yaml            # factory-wide defaults and caps
└── kaos-fleet-manager/
    └── line.yaml           # one governed project == one line
```

Adding a line = adding a directory whose `line.yaml` validates against this schema
AND whose repo passes the admissibility checklist (`project-claude-template.md`).
No core code change.

## Design principles

1. **Invalid states are unrepresentable.** Non-bypassable governance has no
   on/off field. `db_schema` has no `enabled:` key — only its watched paths are
   configurable. You cannot write a YAML that turns it off.
2. **No secrets in the registry.** Tokens are referenced by env var name; values
   live in the factory host `.env`, outside any repo.
3. **Versioned schema.** `schema_version` gates parsing; bumps are documented in
   the project journal.
4. **Registry values are defaults; intake can only move toward *more* human
   control** (raise a plan level, add a gate), except explicit per-task lowering
   by the human where the schema marks it lowerable.

## `line.yaml` — reference with kaos as the worked example

```yaml
schema_version: 1
line: kaos-fleet-manager

repo:
  github: <owner>/kaos-fleet-manager
  default_branch: main
  token_env: DF_GH_TOKEN_KAOS      # fine-grained, this repo only, in host .env

context:
  claude_md: CLAUDE.md             # admissibility contract target
  entrypoints:                     # what the executor reads first, in order
    - CLAUDE.md
    - doc/thermal_controller_technical.md

gates:
  plan:
    default_level: spec            # quick | spec | interview (arch. §3.1)
  merge: {}                        # v1: mandatory, not lowerable; no knobs exist
  deploy:
    enabled: true                  # false for lines with no deploy target
  db_schema:
    watched_paths:                 # detection layer 2 (arch. §3.2)
      - "backend/app/models/**"
      - "**/migrations/**"
      - "**/database_schema.md"

budget:                            # executor sessions (arch. §5)
  daily: 4
  weekly: 15

deploy:
  target: kaosfleet-pi             # symbolic name; resolution in _global.yaml
  runbook: doc/commands.md         # authoritative "how", stays in target repo

observation:                       # defaults for specs that opt into OBSERVING
  source: "sqlite:GroupHeatHistory"
  default_window: 48h

executor:
  image: df-executor:python        # base image family for task containers
  egress_allowlist:                # arch. §7 — exfiltration has nowhere to go
    - api.anthropic.com
    - github.com
    - pypi.org
    - files.pythonhosted.org
```

## `_global.yaml`

```yaml
schema_version: 1

budget:
  global:
    daily: 6                       # < sub cap, with margin for the human's own use
    weekly: 20                     # global < sum(lines) is allowed and expected

escalation:
  reping_hours: 12

concurrency: 1                     # v1 invariant; a field so raising it post-v1
                                   # is a governance decision, not a code change

deploy_targets:
  kaosfleet-pi:
    via: tailscale                 # factory deploys TOWARD the Pi, never runs on it
    host_env: DF_DEPLOY_KAOS_HOST  # tailnet name in .env, not hardcoded
```

## Field rules (the ones that matter)

| Field | Rule |
|---|---|
| `gates.db_schema` | cannot be absent; `watched_paths` cannot be empty for a line with a DB |
| `gates.merge` | must be `{}` in schema v1 — any knob under it fails validation |
| `budget.*` | required; a line without caps fails validation (no unmetered lines) |
| `repo.token_env` | must match `DF_GH_TOKEN_*`; validator checks the env var exists at load |
| `executor.egress_allowlist` | additive over a factory-wide minimum (Anthropic, GitHub); a line cannot remove the minimum, only extend |
| `deploy.target` | must resolve in `_global.yaml`; a dangling target fails at load, not at deploy time |

## Validation

A `validate_registry` script (early factory-repo utility, not a factory task) runs
at orchestrator startup and on registry change: schema check + the field rules
above + env var presence. **Fail-closed: an invalid line does not load**; the
factory reports it on the intake channel rather than running ungoverned.

## Non-goals

Per-task YAML overrides files (per-task changes happen at intake, live in the task
record/trace, never mutate the registry), secrets material, per-line Hermes
config (orchestrator config is host-level, one instance).
