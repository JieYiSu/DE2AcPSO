# DE2AcPSO

Official MATLAB code accompanying the manuscript **"A dual-engine enhanced
adaptive compact particle swarm optimization for high-dimensional expensive
optimization with an evaluation-limited synthetic path-cost study."**

DE2AcPSO alternates a fit-gated restricted-quadratic local engine and an
archive-reconstructed compact global engine with RBF screening. This
repository contains the proposed algorithm, three ablation variants, the
synthetic path-cost problem, experiment runners, statistical analysis code,
tests, and compact result tables.

## Requirements

- MATLAB R2020b or newer is recommended. The release was tested with MATLAB
  R2026a.
- PlatEMO 4.15 or a compatible later release.
- Statistics and Machine Learning Toolbox for `lhsdesign`, `pdist2`,
  `ranksum`, `signrank`, and `friedman`.
- Parallel Computing Toolbox is optional and is used only by parallel
  experiment modes.

PlatEMO is a separate research platform and is not redistributed here. Its
own copyright and usage terms continue to apply.

## Installation

1. Download PlatEMO and note the directory containing `platemo.m`.
2. Clone or download this repository.
3. In MATLAB, run:

```matlab
cd('path/to/DE2AcPSO-open-source');
install_into_platemo('path/to/PlatEMO',true);
addpath(genpath('path/to/PlatEMO'));
```

The second argument controls whether existing DE2AcPSO files are overwritten.
The installer copies only this repository's payload into the matching PlatEMO
folders.

## Quick start

```matlab
bestValue = quick_start('path/to/PlatEMO');
```

Or, after installation, run DE2AcPSO directly:

```matlab
platemo('algorithm',@DE2AcPSO,'problem',@SOP_F11, ...
    'N',50,'D',30,'maxFE',1000,'save',25,'run',1);
```

The default algorithm parameters are `R2Gate = 0.10`,
`PDIProbability = 0.20`, `CandidateMultiplier = 20`, and
`EliteArchiveSize = 50`.

## Reproduce the paper experiments

Run these commands from MATLAB after installation and after adding the
PlatEMO root recursively to the path.

```matlab
% One short installation check
run_DE2AcPSO_benchmark('smoke',false);

% Main benchmark: DE2AcPSO only or all six methods
run_DE2AcPSO_benchmark('paper',false);
run_DE2AcPSO_benchmark('paper',true);

% D = 500 ablation study
run_DE2AcPSO_ablation('paper');

% SOP F11 sensitivity study, D = 30 and 500, 10 paired runs
run_DE2AcPSO_parameter_sensitivity('full',[30 500], ...
    1:18,1:10,true,0);

% Synthetic path-cost study and its figures/statistics
run_DE2AcPSO_path_cost_experiment;
plot_DE2AcPSO_path_cost_results;
```

The full comparison requires `L2SMEA`, `SADEAMSS`, `SAMSO`, `GORS_SSLPSO`,
and `SHPSO` to be available on the MATLAB path. These third-party comparison
implementations are not redistributed by this repository.

Post-process completed PlatEMO result files with:

```matlab
dataDir = fullfile('path/to/PlatEMO','Data');
outputDir = fullfile(pwd,'recomputed-results');
analyze_DE2AcPSO_benchmark_statistics(dataDir,outputDir);
analyze_DE2AcPSO_ablation_statistics(dataDir,outputDir);
```

## Repository layout

```text
platemo/     Files installed into the corresponding PlatEMO directories
examples/    Minimal executable example
results/     Compact CSV summaries and small reproducibility artifacts
docs/        Experiment protocol and data-availability notes
```

Large PlatEMO `.mat` archives are intentionally excluded from GitHub. The
included CSV files contain the processed statistics used by the manuscript.
See `docs/DATA.md` for the recommended raw-data archive workflow.

## Tests

```matlab
results = run_tests('path/to/PlatEMO');
```

## Citation

Citation metadata are provided in `CITATION.cff`. The article DOI and final
bibliographic information should be added after publication. Publications
using this implementation should also acknowledge and cite PlatEMO:

> Y. Tian, R. Cheng, X. Zhang, and Y. Jin, "PlatEMO: A MATLAB platform for
> evolutionary multi-objective optimization," IEEE Computational
> Intelligence Magazine, 12(4), 73-87, 2017.

## License

The DE2AcPSO files in this repository are released under the MIT License.
PlatEMO and all third-party comparison implementations remain subject to
their respective terms.
