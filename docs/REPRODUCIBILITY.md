# Reproducibility protocol

## Main benchmark

- Problems: SOP `F1`, `F5`, `F8`, `F9`, `F10`, `F11`, `F12`, and `F13`.
- Dimensions: 30, 50, 100, 200, 500, and 1000.
- Population parameter: `N = 50`.
- Evaluation budget: `maxFE = 1000`.
- Independent runs: 20 per algorithm-instance pair.
- Algorithms: L2SMEA, SADEAMSS, SAMSO, GORS-SSLPSO, SHPSO, and DE2AcPSO.

The per-instance analysis uses two-sided Wilcoxon rank-sum tests because the
stored main runs were generated independently. Completed comparisons form one
Holm family. Cross-instance analysis uses Friedman tests on instance medians,
paired signed-rank post hoc comparisons of ranks, Holm correction, Kendall's
W, and the Vargha-Delaney A12 effect size.

## Ablation study

- Variants: `DE2AcPSO_wo_ACDP`, `DE2AcPSO_wo_PDI`, and
  `DE2AcPSO_wo_RATR`.
- Problems: the same eight SOP functions.
- Dimension: 500.
- Evaluation budget: 1000.
- Runs: 20.
- Inference: two-sided rank-sum tests with one Holm family across the 24
  variant-function comparisons.

## Parameter sensitivity

- Problem: SOP `F11`.
- Dimensions: 30 and 500.
- Evaluation budget: 1000.
- Paired runs: 10 per level, using common random seeds.
- Base seed: 814729.
- Parameters and levels:
  - `R2Gate`: 0, 0.05, 0.10, 0.20, 0.30.
  - `PDIProbability`: 0, 0.10, 0.20, 0.30, 0.40.
  - `CandidateMultiplier`: 1, 2, 3, 20.
  - `EliteArchiveSize`: 20, 50, 100, 200.

Non-default levels are compared with their paired default by exact two-sided
Wilcoxon signed-rank tests followed by Holm correction. The defaults are a
common robust setting for the tested cases; the study does not claim global
parameter optimality.

## Synthetic path-cost study

- Scenarios: 1 and 2.
- Dimension: 500.
- Evaluation budget: 1000.
- Runs: 20.
- Route samples per objective evaluation: 200.
- Scene seed: 20260731.

This is a synthetic weighted path-cost optimization experiment. It is not a
full collision-free robot planner and does not impose robot dynamics, hard
obstacles, turning-radius constraints, or continuous collision checking.

## Result validation

Only completed histories reaching the evaluation budget are admitted to the
inferential comparisons. Initialization-only or malformed records are marked
unavailable. The included test files check Holm adjustment, effect-size
direction, result loading, parallel sensitivity task deduplication, and the
path-cost plotting/statistics helpers.
