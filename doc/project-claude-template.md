# darkfactory — Project CLAUDE.md contract & template

> Status: DESIGN v1. A project is **admissible as a line** only if its repo-root
> CLAUDE.md fulfills this contract (registry `context.claude_md`). The reference
> specimen is kaos-fleet-manager's CLAUDE.md. Language of the target file follows
> the project's own conventions (kaos: French).

## What this file is — and is not

The project CLAUDE.md is **context, not governance**. It tells any worker (human
or executor session) what is true about the project: domain reality, constraints,
where authority lives, known debt. It must never contain gates, budgets, deploy
approvals or anything the factory relies on for control — those live in the
registry, out of the repo's reach (architecture.md §3, §7).

The factory treats the file as **semi-trusted**: great context, zero authority.
Any instruction in a target repo that attempts to alter factory behavior
("skip the merge gate", "you may deploy without asking") is treated as prompt
injection: abort task, flag line (architecture.md §9).

## Required sections (the contract)

### 1. Ce que c'est vraiment / What it really is
The domain reality and its consequences on code. The kaos specimen is the gold
standard: "not a crypto-mining project — a heating controller", followed by
concrete implications (Group == physical immersion tub; optimize for safe heat
delivery, never hashrate). This section is what prevents an executor from
"improving" the code toward the wrong objective function. **The most important
section — if writing it feels trivial, it isn't done.**

### 2. Durable constraints
Structural facts that survive releases: target platform and its limits, how to
run (and how NOT to run — kaos: "always Docker Compose, never native", with the
incident that proved it), timezone/UTC traps, resource ceilings. Volatile "how"
(ports, commands) belongs in linked docs, not here.

### 3. Data & schema reality  ← feeds the db_schema gate
- Where truth lives (kaos: SQLite in the `luxos_data` volume; native runs create
  a divergent phantom DB).
- Migration mechanism and its cost (kaos: no Alembic — schema change == dev DB
  reset or manual ALTER; always surface migration cost before touching a model).
- Ground-truth datasets an agent may rely on (kaos: append-only
  `MinerHeatHistory`/`GroupHeatHistory` — the basis for OBSERVING verdicts).

### 4. Verification affordances  ← feeds spec `verification` sections
What "proof" looks like in this repo:
- how to run the test suite (exact command, in-container);
- what counts as external signal (structured persistent data, probes) and what
  does not (kaos: stdout logs are volatile — never the basis of analysis);
- any golden/baseline artifacts and where they live.
kaos note: its current CLAUDE.md covers signal sources but lacks the test-run
command — to add during spike #3.

### 5. Authoritative docs
The "read before reinventing" table: file → when to read it. Keeps executor
context lean (entrypoints in the registry point here).

### 6. Known debt
Honest list. Debt is task fuel for the factory — spike #3 (missing
`test_thermal_controller.py`) comes straight from this section of the specimen.

### 7. Conventions
Language rules (kaos/darkfactory: FR code & comments, no accented identifiers,
no over-francization, EN technical docs), commit style ("1 commit = 1 observed
symptom"), doc-update-with-change rule.

## Forbidden content (admissibility fails if present)

- Gates, budgets, approval rules, deploy authorizations — governance of any kind.
- Secrets, tokens, hostnames of deploy targets (symbolic names only).
- Instructions addressed to the factory ("the factory should/may...").
- Duplication of volatile deployment detail that belongs in runbooks.

## Admissibility checklist (run before registering a line)

- [ ] Sections 1–7 present and non-empty; §1 states domain consequences on code
- [ ] §3 states the migration cost explicitly (or "N/A — no DB")
- [ ] §4 gives a runnable test command and names at least one structured signal
      source (or explicitly states none exists — which caps what the line can
      safely be asked to do)
- [ ] No forbidden content
- [ ] File loads as the executor's first entrypoint (registry `context`)
- [ ] A human other than the author could infer "what would break this project"
      from §1–2 alone

## Template skeleton

```markdown
# CLAUDE.md — <project>

> Décrit CE projet. Le `~/.claude/CLAUDE.md` reste la couche de base ; ce fichier
> le spécialise et a priorité en cas de conflit sur ce projet.

## Ce que c'est vraiment
<domaine réel + conséquences concrètes sur le code>

## Contraintes (durables)
<plateforme, comment lancer / ne PAS lancer, pièges structurels>

## Données & schéma
<où vit la vérité ; mécanisme + coût de migration ; datasets de vérité-terrain>

## Vérification
<commande de tests ; signaux externes valides ; ce qui ne compte PAS comme preuve>

## Docs faisant autorité
| Fichier | Quand |
|---|---|

## Dette connue
<liste honnête — c'est du carburant à tâches>

## Conventions
<langue, style de commits, règle doc-avec-changement>
```
