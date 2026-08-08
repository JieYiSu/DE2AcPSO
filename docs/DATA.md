# Data availability

The original PlatEMO result archives contain populations and convergence
histories and occupy several gigabytes. They are intentionally excluded from
GitHub to keep the repository cloneable.

The `results` directory contains compact CSV summaries, the sensitivity raw
table, experiment-status records, and the deterministic path-cost scene
definition. These files are sufficient to inspect the reported summary and
statistical outputs, but not to reconstruct every stored population.

For publication, archive the complete raw `Data` directories in a persistent
research-data repository such as Zenodo or OSF, then add the resulting DOI to
this document and to the manuscript's data-availability statement. Preserve
the original directory names because the supplied analysis scripts use the
PlatEMO naming convention.

The historical path-cost status files use the internal identifier
`obstacle-aware-v2`. This identifier is retained in the archived records for
provenance; the manuscript and current scripts describe the experiment more
accurately as a synthetic path-cost study.
