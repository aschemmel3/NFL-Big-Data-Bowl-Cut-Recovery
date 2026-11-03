# WR cut and recovery drill review

## Decision

Start with the **first comeback cut** as the primary measurement. Keep the **first curl cut in a two-detection attempt** as a separate secondary feature. Do not pool different drills, sides, or first/second cuts into a receiver ranking yet.

This review uses only 2023–2024 WR skill-drill tracking: 992 events, 69 receivers, 14 original drill labels. No NFL outcomes, career-success data, or 2025 tracking enter extraction or drill selection. Source documentation identifies x/y as yards and s as yards/second. These are trajectory turns, not direct measurements of foot plants or body orientation.

## What was visually reviewed

Representative trajectory/speed plots were inspected for all 14 original drill labels. The initial review included a typical entry-speed example and low/high detection-count examples where distinct. Follow-up inspection checked the revised baseline and class-specific examples for comeback, curl, and slot-strike. The final gallery generates 60 examples across both classes; this does **not** mean all 60 final examples or all 992 attempts have been individually approved.

| Drill | Observed geometry and measurement issue | Decision |
|---|---|---|
| Comeback right | Clear principal turn paired with a speed minimum. Some attempts contain a later turn. | Primary candidate: first turn only; stop follow-up at the next detected turn. |
| Curl right | Many examples contain two turns and two speed minima; a no-detection example has a broader path. | Secondary candidate: first turn in exactly two-detection attempts; do not blend with comeback. |
| Slot strike left | Clear low-speed reversal, but the coordinate-speed floor misses visually apparent pivots. | Defer for a dedicated low-speed reversal method. |
| Dagger left / slant left | Typical inspected paths have broader directional transitions; rare dagger detections occur later in atypical paths. | Exclude from the initial sharp-cut feature. |
| Speed out left / speed out route left | Broad turns at the prototype timescale; differing path lengths and label distributions. | Keep labels separate; defer. Similar-looking paths alone do not establish equivalent protocols. |
| Post corner left / right | Different shapes across sides, mostly broader curvature; isolated detections are atypical. | Defer; do not assume equivalent left/right tasks. |
| Slot sail right | Broad multi-phase curve; rare detected turn can be near the end. | Defer. |
| Go / over shoulder adjust / red-zone fade | No sharp-cut detections under the prototype rule. | Exclude from the sharp-cut metric. |
| Gauntlet | Occasional endpoint turn can trigger detection despite a mostly straight traverse. | Exclude; an incidental endpoint turn is not the intended task. |

## Prototype measurement rules

- Sort frames by player, event ID, attempt, timestamp. Reject events with invalid x/y/s, timestamp intervals outside 0.05–0.15 seconds, or centered coordinate speed above 15 yd/s. Earlier coverage audit also checked raw adjacent-frame jumps.
- Use a centered three-frame mean for reported speed. Derive heading from centered coordinate displacement over approximately 0.2 seconds; do not use supplied heading at a stationary pivot.
- Detect at least 45 degrees of net heading change across 0.5 seconds, with coordinate speed at both endpoints at least 2 yd/s. Require net change / total absolute heading change at least 0.8 to reject oscillation. Merge overlapping windows and retain the strongest window. The reported angle is the heading change in that chosen window, **not total route-turn angle**. Merging can still combine closely spaced same-direction turns.
- Choose the fastest stable 0.3-second approach interval in the 1.5 seconds before turn start, ending at least 0.15 seconds before it. Require four frames, speed CV at most 0.10, absolute endpoint speed slope at most 2 yd/s², and mean speed at least 3 yd/s. Preserve a flagged fallback for inspection, but exclude it from candidates. This peak-plateau definition is explicit and still requires sensitivity assessment; it is not a physiologically exact braking-onset measurement.
- Find minimum smoothed speed from 0.2 seconds before the selected turn window to 0.2 seconds after it. Speed-loss fraction is `(approach speed - minimum speed) / approach speed`.
- Measure signed speed gain and mean acceleration during the next 0.5 seconds after that minimum. Require the full follow-up interval before another detected turn or the recording's usable end. Values retain the 0.1-second sample resolution; there is no subframe interpolation.
- Recovery time is measured from the minimum to the first speed at or above 90% of approach speed that persists for 0.2 seconds. Use separate statuses for recovered, no material speed loss, recording-end censoring, and next-cut censoring. Missing recovery remains blank. Follow-up stops conservatively 0.1 seconds before the next detection cluster or final frame because centered estimates need adjacent samples. Undetected later turns can still contaminate follow-up.

## First extraction results

The default detector produces 239 provisional turns across all drills. These include incidental turns and are **not** 239 approved athletic cuts.

| Candidate feature | Attempts | Receivers | Recovery observed | Recovery censored | Full 0.5s speed gain available |
|---|---:|---:|---:|---:|---:|
| First comeback cut | 68 | 63 | 1 | 67 | 68 |
| First curl cut, two-detection attempts | 35 | 35 | 0 | 35 | 35 |

Comeback candidates include 35 receivers from 2023 and 28 from 2024. All 69 comeback attempts contain a detected first cut; one Brian Thomas attempt fails the stable-approach criterion. His other eligible attempt remains represented. Later comeback cuts remain in the provisional table for inspection but are not primary features.

The very high recovery censoring rate is a substantive limitation. Returning to 90% of earlier approach speed often does not occur before the recording ends or the next turn begins. **Use speed loss and fixed-window speed gain as the initial components. Do not rank receivers by averages of the rare observed 90% recovery times.**

Only five receivers have two eligible comeback attempts, and no secondary-curl receiver has repeated eligible attempts. Their spreads are exported, but this sample cannot establish dependable population repeatability or individual uncertainty. One-event medians are simply single observations.

## Sensitivity and verification

The full 3×3 grid (30/45/60 degrees; 0.3/0.5/0.7 seconds) is exported. At 45 degrees, comeback event detection is 28/69 at 0.3s and 69/69 at both 0.5s and 0.7s. At 60 degrees/0.5s, it drops to 51/69. Slot-strike detection rises from 40/64 at 45 degrees/0.5s to 63/64 at 0.7s; this supports deferring its low-speed pivot rather than labeling the other 24 receivers poor cutters. Curl turn counts and grouping also change materially. Coverage stability does not prove feature-value or ranking stability.

Checks passed for synthetic straight travel (zero detections), an isolated right-angle turn (one), rotation invariance, a timestamp gap (rejected), interrupted recovery (blank/censored), and observed sustained recovery. Output checks enforce unique event-cut keys, development years only, sufficient candidate follow-up, and recovery times within observed follow-up. These verify implementation behavior, not empirical validity.

## Files and reproduction

Run `node review_wr_cuts.mjs`, then `./render_cut_review.ps1`. Open `index.html` for the gallery.

- `provisional_cut_events.csv`: all detections, flags, entry windows, speed-loss and recovery components, candidate designation.
- `event_cut_coverage.csv`: includes attempts with no detections.
- `candidate_player_drill_features.csv`: separate provisional receiver/drill summaries, event counts, censor counts, and repeated-measurement indicators. Not a combined score or ranking.
- `repeated_attempt_spread.csv`: within-player ranges for the five repeated comeback measurements.
- `detection_sensitivity.csv`: detection counts by drill and parameter setting.
- `review_examples.json` and PNGs: trajectories and speed curves for reviewing the rules.

Next validation should check first-cut alignment and feature-value stability across detector settings, manually adjudicate anomalous attempts, and test whether shuttle/cone tracking can add repeatable complementary cuts. Any normalization for entry speed, turn angle, and drill must be fitted on training players only. No predictive model or combined athletic score has been fitted.
