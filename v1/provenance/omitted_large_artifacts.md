# v1 omitted artifacts

The v1 release archive intentionally excludes posterior RDS files, cached compiled objects, Python runtime caches, and visual-review duplicates because they are too large or platform-specific for a normal Git repository. The original formal v1 run contains 225 RDS objects totaling about 75.1 GB. The original v1 workflow, input files, manuals, result tables, figure data, figure PDFs/SVGs, figure captions, manifests, and the exact source hashes are included. Re-running the v1 workflow recreates the omitted posterior objects.
