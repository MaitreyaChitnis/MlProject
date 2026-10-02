# MIT-BIH data manifest

This file exists so anyone (professor, external reviewer, future you) can verify
exactly which data this project used, without needing the raw files committed to git.

## Source
- Database: MIT-BIH Arrhythmia Database
- Provider: PhysioNet (https://physionet.org/content/mitdb/)
- Version: v1.0.0
- Sampling rate: 360 Hz, two-lead recordings (Lead II used unless noted otherwise)
- Total records in database: 48 (patient IDs in ranges 100–124 and 200–234, with gaps)

## Records actually used in this project
- Total used: 44 (per AAMI EC57 recommendation)
- Excluded: 102, 104, 107, 217 (paced-beat patients — see ds1_ds2_split.json for reasoning)
- Train/test split: see `data/splits/ds1_ds2_split.json` (this is the single authoritative
  list — do not hand-type record numbers anywhere else in the codebase; import from this file)

## How to reproduce the raw data locally
1. Run `scripts/download_mitbih.sh` (pulls all 48 records from PhysioNet).
2. Verify file counts: each of the 48 records must have exactly 3 files
   (`<id>.dat`, `<id>.hea`, `<id>.atr`) in `data/raw/`.
3. Optional integrity check: PhysioNet publishes per-file checksums on the database
   page — run a checksum comparison against those if you need to prove the data
   wasn't altered after download (recommended before final submission).

## Verification checklist (run before trusting any downstream result)
- [ ] `ds1_training` list has exactly 22 entries
- [ ] `ds2_testing` list has exactly 22 entries
- [ ] No record ID appears in both lists (patient-level leakage check)
- [ ] `excluded_paced_patients` (102, 104, 107, 217) are not loaded anywhere in either track
- [ ] Both Track A and Track B code import record lists from `ds1_ds2_split.json` —
      neither script hard-codes its own copy of the numbers
