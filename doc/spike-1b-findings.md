# SPIKE #1b — Findings: terminal backend `local` → `docker`

> Date: 2026-07-19. Status: **PASS (core) + 2 hardening items documented**.
> Context: CLAUDE.md, architecture.md §7, project-journal.md (spike #1 + issue #300/#35).
> Companion to the entry in `doc/project-journal.md` (same date).

## Verdict in one line

Hermes with `terminal.backend: docker` runs a full `claude -p` session **inside a
disposable container** — authenticated, working on the mounted task repo, with the
result captured fail-closed and **zero code executed on the host**. The trust-boundary
violation observed in spike #1 (orchestrator running `pytest`/`venv` on the VPS host)
is closed. Two items are designed-and-partially-verified, not fully stress-tested:
**per-task container teardown** and **egress allowlist**.

## What was validated (empirical, not by principle)

| PASS criterion | Verdict | Evidence |
|---|---|---|
| `claude -p` authenticates + runs **in** the container | **PASS** | isolated `docker run` with read-only creds mount returned `subtype: success` (`result: pong`); container hostname/cgroup/`whoami=root` confirm containerization |
| calc.py + test_calc.py created in mounted repo; pytest passes in container | **PASS** | via Hermes terminal(docker) → `claude -p` → 4/4 pytest green, files land in the bind-mounted repo on the host |
| Hermes captures structured JSON (`subtype: success`) | **PASS** | full JSON payload returned intact through the oneshot orchestrator |
| No host artifacts outside the mounted repo | **PASS** | no `.venv`/`__pycache__`/pytest on host `~`; the spike #1 host-pollution bug does not reproduce |
| Result capture is fail-closed | **PASS** | a failing `claude` returns `subtype: error_max_turns`, `is_error: true`, `result: null`, **exit code 1** — no silent success |
| Container destroyed after the task (disposable) | **PARTIAL** | Hermes does **not** auto-destroy (see Finding 4); explicit teardown by label works and is darkfactory's responsibility |
| Egress allowlist enforced | **PARTIAL / documented** | default egress is wide open (verified); `--internal` network blocks all egress with no root (verified); domain-allowlist proxy is the recommended path, **not yet stress-tested** |

## The auth mount mechanism (exact, reproducible — the core of the spike)

The delicate point (a fresh container has no `~/.claude`) resolved cleanly:

- Claude Code's OAuth (subscription) auth lives in a **single file**:
  `~/.claude/.credentials.json` (600, ~500 bytes). That is all `claude -p` needs to
  authenticate headless — no interactive login, no `ANTHROPIC_API_KEY`.
- The container's `HOME` is `/root`. In disposable mode (`container_persistent:
  false`) `/root` is a **tmpfs** — writable and gone on destroy. `claude` writes its
  cache / session / history there without issue; only the credentials file is mounted.
- **Mount mechanism = `docker_volumes` (read-only bind):**
  ```
  /home/inverted/.claude/.credentials.json:/root/.claude/.credentials.json:ro
  ```
- **Why not Hermes' native credential-mount path** (`required_credential_files` in a
  skill, or `terminal.credential_files` in config)? Both are hard-confined to
  `HERMES_HOME` (`~/.hermes`) with anti-traversal — by design, so a malicious skill
  can't declare `../../.ssh/id_rsa`. Our auth lives in `~/.claude`, **outside**
  `~/.hermes`, so neither native path can reach it. `docker_volumes` is trusted
  operator config (not skill-declared), so using it here does not weaken that policy.
- **Read-only is sufficient.** `claude` did not need to write the credentials file for
  a short task (token was fresh; refresh not triggered). This validates architecture
  §7's "creds read-only + egress allowlist = exfiltration with nowhere to go" premise
  on the auth half. If a long task ever needs a token refresh, the write would fail
  silently against the ro mount — see Open items; do **not** widen to rw by reflex.

## Final docker config (what makes the gateway containerize)

`~/.hermes/config.yaml`, `terminal:` section:

```yaml
terminal:
  backend: docker            # gateway reads THIS key
  env_type: docker           # CLI/oneshot path reads THIS key (see Finding 3)
  cwd: /home/inverted/tasks/spike1b-calc   # a DEDICATED task dir, never $HOME
  timeout: 180               # not re-tuned blindly; calc task ~12s fits
  home_mode: auto
  container_cpu: 1
  container_memory: 5120
  container_disk: 51200
  container_persistent: false          # disposable: tmpfs /root, no reuse-by-turn
  docker_mount_cwd_to_workspace: true  # the task repo becomes /workspace in-container
  lifetime_seconds: 300
  docker_image: darkfactory-task-runner:claude-2.1.207
  docker_volumes:
    - /home/inverted/.claude/.credentials.json:/root/.claude/.credentials.json:ro
```

**cwd must be a dedicated task dir, never `$HOME`.** With
`docker_mount_cwd_to_workspace: true`, the host cwd is bind-mounted to `/workspace`;
pointing it at `/home/inverted` would expose `~/.claude` and `~/.hermes` to the
container. Scoping to a per-task repo dir enforces "mount the task workdir, never a
shared state volume" (spike prompt / issue #300 secondary bug).

## The task-runner image (pinned hard — lesson from issue #300)

`docker/task-runner.Dockerfile`, built by `setup.sh` (§5b). Not a local-only image —
Dockerfile is versioned in the repo, build is scripted, so the server stays
reconstructible.

- Base **pinned by digest**, not a floating tag:
  `nikolaik/python-nodejs@sha256:8f958bdc1b4a422bfafd97cab4f69836401f616ae985d4b57a53d254f5bcb038`
  (resolved 2026-07-19 from `python3.11-nodejs20`). Ships git 2.47 / python 3.11 /
  node 20 / npm — the whole dev base.
- `claude-code` **pinned to the exact host known-good version**: `2.1.207` (the one
  that PASSed spike #1). The build **fails loud** if the installed version drifts from
  the requested one — the opposite of issue #300's silent bad-SHA failure.
- No secret in the image: auth is mounted read-only at run, never baked in.

## Findings / frictions (the design deltas)

1. **The default backend image has no `claude`.** Hermes' docker backend defaults to
   `nikolaik/python-nodejs:...` (python+node only). "Flip the flag and validate" is
   impossible as written — the image is a prerequisite. Resolved by the pinned
   task-runner image above.

2. **Native credential-mount can't reach `~/.claude`.** Confined to `HERMES_HOME` by
   design. `docker_volumes` (trusted operator config) is the correct escape hatch.

3. **`backend` vs `env_type` — two key names for one setting.** The gateway config
   bridge reads `terminal.backend`; the CLI/oneshot bridge reads `terminal.env_type`.
   A config with only `backend: docker` makes the **gateway** containerize but leaves
   the **CLI oneshot** running `local` (observed: first test ran on the host). Both
   keys are set in the final config. This is a footgun for anything that drives Hermes
   outside the gateway (tests, scripts) — darkfactory's own harness must set the
   `TERMINAL_*` env explicitly or both keys, or it will silently test the wrong
   backend. **Do not trust a single key to mean "docker everywhere."**

4. **Containers are NOT auto-destroyed per task.** Hermes runs the container as
   `sleep infinity` and relies on an **idle reaper** (`~2 × lifetime_seconds`) plus
   **cross-process reuse by label** (`docker_persist_across_processes`, default on).
   So "disposable" in Hermes means "reused between turns, reaped when idle" — **not**
   "one container per task, killed on task end." This contradicts architecture §2's
   invariant ("`EXECUTING` is the only state where a container exists; leaving it kills
   the container"). **Consequence: container teardown is darkfactory's responsibility,
   not Hermes'.** The state machine must `docker rm -f` the container labeled
   `hermes-task-id=<task>` when the task leaves `EXECUTING` (verified: teardown by
   label works). Also set `docker_persist_across_processes: false` so tasks don't
   silently share a container.

5. **Files created in the mounted repo are owned `root:root` on the host.** The
   container runs as root (image default); bind-mounted writes surface as root on the
   host. The `inverted` operator then can't edit/delete task outputs without sudo, and
   git operations on the mounted repo mix ownership. Options: (a)
   `docker_run_as_host_user: true` (writes owned by uid 1000 — but interacts with
   `HOME=/root`/tmpfs perms and the creds mount, must be tested), or (b) a chown step
   at task teardown. **Decide before wiring git push into the task-runner.**

6. **Egress is wide open by default; `--internal` contains it with no root.** A stock
   task container reaches api.anthropic.com **and** example.com **and** 1.1.1.1
   (verified) — exfiltration has a destination. Host-firewall allowlisting
   (iptables/nft `DOCKER-USER`) is **root-only** (sudo needs a password in this
   session) and IP-based allowlisting is brittle against CDN churn (anthropic/github/
   pypi are all CDN-fronted). **Better, root-free, durable design:** a Docker
   `--internal` network (verified to block *all* egress) + a **dual-homed domain-
   allowlist proxy** (attached to both the internal net and a normal bridge) as the
   single controlled egress; task container joins via `docker_extra_args:
   ["--network","df-egress"]` and gets `HTTPS_PROXY`/`HTTP_PROXY` → proxy. A CONNECT
   proxy also removes the container's need for external DNS (the proxy resolves).
   **Open item:** stand up the proxy and stress-test (does Claude Code honor
   `HTTPS_PROXY`? does the CONNECT allowlist pass api.anthropic.com and block the
   rest?). This matches the journal's standing gate: harden + test the allowlist
   before the first unattended overnight run.

7. **Fail-closed signature observed.** A failed `claude -p` →
   `{subtype: error_max_turns, is_error: true, result: null}` + **non-zero exit**. A
   capture that checks exit code **and** `is_error`/`subtype` (never `|| true` /
   `2>/dev/null`) fails closed. This is the concrete shape architecture §5 asked for
   (`result_is_error` + fast non-zero exit); the exhausted-window class will look
   similar and must be routed to the environment-level pause, not a per-task failure.

## Recommendation for the task-runner

- **Image:** the pinned `darkfactory-task-runner` (Dockerfile in repo, built in
  setup.sh). Bump = an explicit, reviewed commit to the Dockerfile; never a floating
  tag or an unpinned `npm install`.
- **Auth:** read-only `docker_volumes` bind of `~/.claude/.credentials.json` →
  `/root/.claude/.credentials.json`. Keep it read-only.
- **Isolation:** `container_persistent: false` + `docker_persist_across_processes:
  false` + **explicit teardown by `hermes-task-id` label** owned by the darkfactory
  state machine. Do not rely on the idle reaper for governance.
- **Workspace:** dedicated per-task repo dir mounted to `/workspace`; never `$HOME`.
- **Egress:** `--internal` network + domain-allowlist proxy (design above); gate the
  first overnight run on stress-testing it.
- **Ownership:** decide `docker_run_as_host_user` vs teardown-chown before the
  task-runner does `git push`.

## What this resolves of the `[SPIKE #1]` markers in architecture.md

- §7 "validate headless auth via read-only mount + allowlist egress in practice" —
  **auth half DONE** (read-only mount works); **egress half DESIGNED, not stress-
  tested** (Finding 6).
- §7 "the executor runs entirely inside the task container, never on the host" —
  **now empirically true** via the docker backend (was violated under `local`).
- §6 "exact capture format from `claude -p --output-format json`" — **known**: the
  result JSON (`subtype`, `is_error`, `total_cost_usd`, `modelUsage`, `session_id`)
  is captured intact by Hermes.
- §5 "observe the exact signature of an exhausted-window `claude -p` call" —
  **partially**: the failure shape (`is_error` + non-zero exit + null result) is
  confirmed on a `error_max_turns`; the true window-exhaustion case still to be seen
  in the wild.

## Open items (carry forward)

- Stress-test the egress proxy (Finding 6) — **gates the first unattended overnight
  run.**
- Decide container-ownership strategy (Finding 5) before wiring `git push`.
- Build darkfactory's explicit container teardown (Finding 4) into the state machine.
- Watch for a real token-refresh-against-ro-mount failure on a long task (auth section).
- `setup.sh:80` still installs host `claude` **unpinned** — same issue #300 trap, out
  of this spike's scope but worth pinning when touched.
