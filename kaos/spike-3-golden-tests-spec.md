# Spike #3 target spec — golden tests for kaos thermal controller

> Status: TASK SPEC. This is the spec the factory receives for its benchmark task,
> written per darkfactory architecture §3.1 (level: `spec`) with a `verification`
> section. Target repo: kaos-fleet-manager. Deliverable:
> `tests/test_thermal_controller.py`.

## Goal (the decision this work serves)

Freeze the CURRENT behavior of the thermal decision logic before any recalibration
of the widened constants (`T_SOFT_HYST`, `RATE_HIGH`, `COOLDOWN_SEC` — see kaos
CLAUDE.md "Calibration thermique"). The goldens are the safety net that makes the
recalibration hypothesis testable. **Characterization, not judgment: if current
behavior looks wrong, the test pins it down and a comment flags it — no fixes.**

## Scope

Two pure(-ish) units, zero I/O:

1. `compute_rate(samples)` — pure function, least-squares slope on a sliding
   window.
2. `ThermalController._calculate_next_applied(...)` — the decision tree.
   Instantiate the controller; do not start its loop.

**Out of scope:** `_tick`/`_process_*` (DB + LuxOS I/O), `_apply_heat_level`
(profile mapping), `_boot_reconcile`, any refactor of the module, any constant
change. No new dependencies beyond pytest.

## Harness decisions (binding)

- **No time-freezing library, no refactor for testability.**
  `_calculate_next_applied` reads `datetime.utcnow()` internally; tests build
  relative timestamps at call time
  (`last_decrease_ts = datetime.utcnow() - timedelta(seconds=N)`). Millisecond
  drift is irrelevant at the tested boundaries (±1 s margins).
- **Inputs expressed relative to module constants**, not magic numbers:
  `temp_max=T_SOFT - 0.1`, `rate=RATE_HIGH / 2`, etc. The suite freezes the TREE;
  a deliberate future constant recalibration must not invalidate structurally
  valid cases.
- **Reasons asserted by stable prefix/class, not full string** (formatted floats
  embedded in reasons would make goldens brittle to cosmetic changes). Classes:
  `Temp > Limit`, `Inertia`, `Temp > Soft`, `Anti-thrash`, `Ramp interval`,
  `Target reached`, `Cooling down`, `User requested lower`, `Stable`.
- Table-driven (`pytest.mark.parametrize`), one table per branch below.

## Case matrix — `_calculate_next_applied`

### Branch A — hard limit (`temp_max >= T_LIMIT`)
| case | inputs (relative) | expected |
|---|---|---|
| A1 drop-2 | temp=T_LIMIT, rate=0, applied=10, desired=15 | 8, `Temp > Limit` |
| A2 floor | temp=T_LIMIT+1, rate=0, applied=2 | 1 (max(1, applied-2)) |
| A3 floor-same | temp=T_LIMIT+1, rate=0, applied=1 | 1 — same level returned, reason still `Temp > Limit` |
| A4 inertia | temp=T_LIMIT+1, rate=-0.001, applied=10 | 10, `Inertia` (cooling, give it time) |
| A5 panic overrides inertia | temp=T_LIMIT+3.0, rate=-0.001, applied=10 | 8 — inertia ignored at limit+3 (boundary: `<` so exactly +3.0 panics) |
| A6 user-lower wins | temp=T_LIMIT, rate=0, applied=10, desired=3 | 3, user-desired reason |

### Branch B — soft limit / high rate (`temp >= T_SOFT or rate >= RATE_HIGH`)
| case | inputs | expected |
|---|---|---|
| B1 soft drop-1 | temp=T_SOFT, rate=0, applied=10 | 9, `Temp > Soft` |
| B2 rate-only drop | temp=T_SOFT-5, rate=RATE_HIGH, applied=10 | 9 — pure rate trigger, temp well below soft |
| B3 inertia | temp=T_SOFT+0.5, rate=-0.001, applied=10 | 10, `Inertia` — note guard requires temp>=T_SOFT; a pure-rate trigger can never satisfy rate<0 |
| B4 boundary | temp=T_SOFT-0.01, rate=RATE_HIGH-0.001 | falls through to C/D, no drop |
| B5 user-lower wins | temp=T_SOFT, rate=0, applied=10, desired=2 | 2 |

### Branch C — raise zone (`temp <= T_SOFT - T_SOFT_HYST and rate <= RATE_HIGH/2`)
| case | inputs | expected |
|---|---|---|
| C1 target reached | temp=low, rate=0, applied=desired=10 | 10, `Target reached` |
| C2 above target | applied=12, desired=10 (in raise zone) | 12, `Target reached` (documents: raise branch never lowers) |
| C3 plain raise | applied=5, desired=10, no timestamps | 6, `Cooling down` |
| C4 anti-thrash | as C3 + last_decrease_ts = now-(COOLDOWN_SEC-10)s | 5, `Anti-thrash` |
| C5 cooldown expiry | as C3 + last_decrease_ts = now-(COOLDOWN_SEC+10)s | 6 |
| C6 ramp hold | as C3 + last_change_ts = now-(RAMP_INTERVAL_SEC-10)s | 5, `Ramp interval` |
| C7 ramp expiry | as C3 + last_change_ts = now-(RAMP_INTERVAL_SEC+10)s | 6 |
| C8 override | as C4 AND C6 with cooldown_override=True | 6 — override bypasses both holds |
| C9 boundary | temp=T_SOFT-T_SOFT_HYST exactly, rate=RATE_HIGH/2 exactly | raise branch taken (both comparisons inclusive) |

### Branch D — hysteresis zone (everything else)
| case | inputs | expected |
|---|---|---|
| D1 stable | temp=T_SOFT-1 (inside hyst band), rate=0, applied=desired | applied, `Stable` |
| D2 user-lower immediate | same temp, applied=10, desired=4 | 4, `User requested lower` — no cooldown/ramp applies |
| D3 rate-blocked raise | temp=low (raise zone temp), rate=(RATE_HIGH/2)+ε, applied<desired | applied, `Stable` — documents that a raise is blocked by rate in (RATE_HIGH/2, RATE_HIGH) |

## Case matrix — `compute_rate`

| case | samples | expected |
|---|---|---|
| R1 empty / single | [], [(t,60)] | 0.0 |
| R2 short span | 2 pts, span = MIN_RATE_SPAN_SEC - 1 | 0.0 |
| R3 zero den | all identical timestamps | 0.0 (guarded) |
| R4 true ramp | linear +0.05 °C/s over RATE_WINDOW_SEC | ≈0.05 (±1e-6) |
| R5 flat quantization flicker | 60↔61 alternating around stable value over full window | ≈0 (< RATE_HIGH/2) — the artifact the window kills |
| R6 single 1 °C step mid-window | flat 60 then flat 61, step at window midpoint, samples every 10 s | **characterize**: assert exact computed slope; expected order ~0.011–0.017 °C/s — BELOW RATE_HIGH (no false safety drop) but ABOVE RATE_HIGH/2 (raise transiently blocked). Comment must state this explicitly: residual quantization effect gates raises, not safety. |

R6 + D3 together pin down, in executable form, the residual artifact relevant to
the calibration hypothesis (kaos CLAUDE.md): the 1 °C sensor resolution no longer
causes spurious safety cuts but can still transiently hold back ramp-ups.

## Verification (spec contract — architecture §3.1)

- `pytest tests/test_thermal_controller.py` green, in-container, no network, no DB.
- Coverage of `_calculate_next_applied` == 100% branches (it's the point of goldens);
  `compute_rate` 100% lines. No coverage requirement on anything else.
- Zero modifications outside `tests/` (the diff proves characterization-only).
- Reason assertions use the prefix classes above — a full-string assert is a
  review-reject.
- External signal: none needed — pure logic, simulated inputs (OBSERVING not
  applicable; see architecture §4b for why this differs from algo-change tasks).

## Side deliverable (same PR)

Update kaos CLAUDE.md "Calibration thermique" section: the rate fix is no longer
"stamp on true variation" — it is a least-squares sliding window
(`compute_rate`, RATE_WINDOW_SEC=90, MIN_RATE_SPAN_SEC=30). Add the R6/D3 finding
(residual artifact moved from safety cuts to raise gating). Per kaos conventions:
behavior-doc update ships in the same change.
