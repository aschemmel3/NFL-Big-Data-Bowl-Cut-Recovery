# Rookie WR separation and career success: exploratory comparison

Reproduce with `./compare_wr_success.ps1`. Inputs are the existing audited WR rookie-route means and supplied career-success table. Separation is measured at pass forward. Each receiver has equal weight; missing separation is excluded, never replaced with zero.

Primary descriptive sample: 62 WRs with at least 50 measured rookie routes. Success definitions are (1) any supplied original-ballot Pro Bowl or AP All-Pro honor and (2) top quarter in cumulative offensive snaps within draft class, thresholds defined among all WRs before separation exclusions, including threshold ties. The latter is a playing-time proxy, not a receiving-production measure. Results include separate class comparisons and pooled summaries; pooled differences are not regression-adjusted for class or route context.

| Definition | Higher-success n | Other n | Higher-success mean | Other mean | Difference, yards | 95% bootstrap interval |
|---|---:|---:|---:|---:|---:|---|
| Any honor | 4 | 58 | 3.273 | 3.117 | +0.155 | -0.175 to +0.422 |
| Top-quarter career offensive snaps within class | 28 | 34 | 3.042 | 3.197 | -0.155 | -0.356 to +0.042 |

The top-quarter snap comparison changes direction across classes: 2023 -0.432 yards, 2024 +0.164 yards, 2025 -0.129 yards (rounded; see CSV for exact values). There is no consistent descriptive pattern that higher-success receivers have greater raw rookie separation. Neither pooled primary interval excludes zero. Intervals use 2,000 receiver bootstrap replicates within draft-class/success strata, with a fixed seed. Very small honored strata make those intervals especially limited; they should not be read as strong inferential evidence.

The honored players' rookie separation means are Jaxon Smith-Njigba 3.54, Marvin Mims 3.36, Puka Nacua 2.77, and Chimere Dike 3.42 yards. The file does not identify the position or role for each award, so return honors may not reflect receiving success.

Sensitivity using any measured routes includes 79 players. Honor difference falls to +0.051 yards; top-quarter snap difference is -0.282 yards. Low-volume receivers materially affect the result. Players without measured separation are outside both comparisons, so selection and missingness remain concerns.

Raw separation depends on route depth/type, coverage, alignment, and usage. Offensive snaps measure opportunity and durability as well as performance. Career and rookie measurement windows overlap; this is association, not prospective validation or causation. The career file supplies no receiving production fields. A stronger follow-up is a common-window receiving-production outcome derived from player_play, paired with route-context-adjusted rookie separation.

This user-requested exploratory analysis includes 2025 outcomes. It is separate from the combine-feature pipeline. Do not tune features based on 2025 player-level findings and then describe 2025 as a fully untouched research holdout; any subsequent evaluation must disclose this exposure.

## Added NGS catch/incompletion separation

Run `./include_ngs_separation.ps1` after the original comparison. The new `wr_success_with_ngs.csv` retains all 106 WRs and adds explicitly named catch-or-incompletion separation, NGS targets, and availability. Unmatched metrics remain blank. The join uses nfl_id and rookie draft year and rejects duplicate supplement keys.

The existing local supplement contains REG season-summary rows (week=0), with 27 matched WRs: 11 in 2023, 11 in 2024, and 5 in 2025. All 27 have at least 50 measured competition rookie routes. These season summaries are not restricted to the competition's exact games and weeks. NGS measures separation on targets at catch or incompletion; the competition mean measures all available routes at pass forward. Their difference cannot be interpreted as receiver separation gained during ball flight.

On the identical 27-player sample, honored receivers (n=3) average 3.51 yards of catch/incompletion separation versus 2.97 for others (n=24). Top-quarter career-snap receivers (n=18) average 2.97 versus 3.15 for others (n=9). These are descriptive, equally weighted receiver means without uncertainty estimates or context adjustment. The mixed pattern and selected sample do not validate either metric as receiving success. See `wr_success_ngs_groups.csv` for class-specific and pooled values.

JSN's rookie NGS separation is 3.79 yards on 93 targets, alongside 3.54 yards at throw across his measured competition routes. Catch-only separation is unavailable in this supplement.

Definition verified against https://nflreadr.nflverse.com/articles/dictionary_nextgen_stats.html . Original external-data provenance and limitations remain in `data/external/nflverse/README.md`.
