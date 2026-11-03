# Combine cut recovery and NFL separation

## Verified coverage

Run `audit_wr_coverage.ps1` from the project directory to regenerate the CSV and JSON reports. The audit uses player entity tracking only and NFL routes with a route label, no nullifying penalty, REG season type, and season equal to draft year.

| Draft class | WRs | WR skill tracking | Complete 40/cone/shuttle | Rookie separation available | At least 50 measured routes |
|---|---:|---:|---:|---:|---:|
| 2023 | 38 | 38 | 10 | 29 | 25 |
| 2024 | 31 | 31 | 7 | 27 | 20 |
| 2025 | 37 | 37 | 8 | 23 | 17 |

There are 14,733 measured rookie-route separation observations, including 11,727 on nontargeted routes. All 3,006 targeted routes have separation; 1,947 nontargeted routes lack it. Inspect missingness by pass result, route, team, and class before fitting. Do not treat missing separation as zero. Only 79 distinct receivers have any outcome; 62 have at least 50 measured routes. Tracking coverage does not establish valid cut coverage.

## First implementation

1. Extract cuts from WR skill drills. Dagger and slant left cover all 106 players; curl right covers 102 and comeback right 97. Inspect paths before selecting comparable cuts. Normalize spelling aliases such as SPEED_OUT_LEFT versus SPEED_OUT_ROUTE_LEFT only after checking trajectories. Exclude straight go routes and gauntlet from the initial sharp-cut metric. Retain shuttle and cone as a smaller validation sample.
2. Sort by player, event, and timestamp. Check duplicate frames, time gaps, coordinate jumps, and speed versus coordinate displacement. Use actual elapsed time. Derive signed speed change from smoothed speed rather than assuming supplied acceleration is signed. Detect sustained direction change from moving trajectory segments; avoid using heading at near-zero speed. Inspect representative paths and speed curves manually before batch extraction.
3. Prototype a 45-degree net turn within 0.5 seconds, with sensitivity checks for 30/60 degrees and 0.3/0.7 seconds. Merge overlapping detections. Define entry speed from a stable precut interval, minimum speed inside the turn, recovery to 90% of entry speed, and speed gain over 0.5 seconds after the minimum. Record angle, turn duration, drill, side, entry speed, and valid follow-up duration. Flag subsequent cuts and truncated recordings. Never interpret missing recovery as instantaneous recovery or silently drop every unrecovered cut.
4. Retain speed-loss fraction and recovery separately first. Adjust for entry speed, angle, and drill with a simple regularized model. Fit transformations on training players only. Aggregate residual performance by player, assess repeatability, and report event counts. Build a combined score only if its components are stable; freeze prespecified weights or learn weights inside nested training folds.
5. Start with rookie separation at pass forward in yards. Fit route-level context using route, coverage, cushion, motion, formation, alignment, and time to throw; inspect field availability first. Evaluate receiver-level average adjusted separation. Weight receivers equally for the main comparison, with route-volume weighting as sensitivity analysis. This is a custom adjusted separation outcome, not a supplied proprietary Average Separation Score.
6. Compare identical player samples: 40 baseline; traditional baseline (40, split, cone, shuttle, height, weight); traditional plus cut components; traditional plus compact score. Fit imputation and missingness indicators inside each training fold. Also report a complete-case sensitivity analysis, recognizing that only 25 WRs have all three main traditional tests before outcome exclusions. Keep NFL context identical across comparisons. Exclude draft pick and career outcomes from primary prospect predictors.
7. Develop with player-grouped cross-validation on 2023 and 2024 prospects. Keep 2025 prospects untouched until features and settings are fixed. With only 23 test receivers having any measured separation, report uncertainty prominently. Compare rookie regular seasons and check actual week coverage. Use the same eligible test players for every model. Bootstrap paired errors by player and report MAE and rank correlation. Route-level random splits are invalid for unseen-prospect evaluation.
8. Only after held-out improvement, examine slower-40 receivers whose tracking predictions improve and whose NFL outcomes support the increase. Compare draft position descriptively to flag potentially overlooked players. Do not claim causal effects or economic undervaluation from predictive uplift alone.

## Scope

Begin with WRs. CB and safety drills can support position-specific movement metrics later, but the available nearest-defender separation outcome is not automatically a defender-level coverage label. The game-tracking files contain cohort players, so nearest-defender distances calculated from them would be incomplete.

## Deliverables still to build

- Quality-reviewed cut-event table and diagnostic trajectory plots.
- Player-level cut features with uncertainty and repeatability checks.
- Route-outcome missingness and season-completeness audit.
- Leakage-safe training pipeline and held-out model comparison.
- Receiver results with measured outcomes and uncertainty.

The coverage audit is complete. A provisional development-only cut extractor and representative drill review are now available; no predictive model has been fitted.

## Development tracking diagnostics started

Run `./audit_wr_tracking.ps1` to regenerate `reports/tracking/development_event_quality.csv`, `development_summary.json`, and `development_diagnostics.html`. This stage reads only 2023–2024 WR skill tracking; 2025 is excluded. Events are keyed by player, event ID, and attempt; drill spellings remain separate.

The initial run contains 992 events from 69 development receivers and creates 14 drill-label examples. It found zero duplicate timestamps, gaps over 150 ms, or coordinate-derived speeds above 15 source distance units per second. These checks do not establish cut validity. The HTML includes equal-scale trajectory plots and reported speed against elapsed time for manual review. The speed-error column compares coordinate displacement per elapsed second with the adjacent-frame average reported speed.

The subsequent review and provisional extraction are documented in `reports/cuts/DRILL_REVIEW.md`. Run `node review_wr_cuts.mjs` and `./render_cut_review.ps1`. The first comeback turn is the primary candidate (68 attempts, 63 receivers), with first curl turns retained separately (35 attempts/receivers). Full 90% recovery is usually censored; speed loss and fixed 0.5-second speed gain are the initial usable components. Feature repeatability and parameter stability remain unproven. See the report for drill exclusions, review scope, and limitations; these are not validated prospect rankings or predictive evidence.
