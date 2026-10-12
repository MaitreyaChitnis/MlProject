# Track A: data, denoising and R-peak detection (draft)

> Draft built only from outputs produced in this project. Items marked **[check]** should be
> confirmed against the code or a paper before submission. Results of the classification
> comparison are NOT in this section; they belong in the Stage 5 / integration report.

## 1. Data and split
- Database: MIT-BIH Arrhythmia Database (PhysioNet), 360 Hz, two leads. Records were read with
  our own MATLAB readers (header, format-212 signal, annotation files); no external toolbox.
- 44 of the 48 records were used. Records 102, 104, 107 and 217 (paced patients) were excluded.
- Patient-level split: 22 records for training (DS1) and 22 for testing (DS2), fixed in
  `data/splits/ds1_ds2_split.json` (the inter-patient DS1/DS2 split of de Chazal et al., 2004
  **[check the reference]**). No patient appears in both sets (asserted in code).
- Lead: MLII, chosen by name from the header. Record 114 stores the leads in the opposite
  order (V5 first), so choosing "column 1" would have used the wrong lead for that record.

## 2. Annotations
- The annotation files contain 103,724 annotations in the 44 records. Only beat annotations
  are kept (N L R e j / A a J S / V E / F / / f Q), giving 100,733 beats. The 2,991 removed
  annotations were rhythm-change markers (1,173), comments (437) and 1,381 codes that are not in the
  beat list and that our reader could not name (written as `?`; probably signal-quality and
  artefact markers **[check which codes they are]**).
- Beats were grouped into the five AAMI classes. Beats per class:

| | N | S | V | F | Q | Total |
|---|---|---|---|---|---|---|
| DS1 | 45,866 | 944 | 3,788 | 415 | 8 | 51,021 |
| DS2 | 44,259 | 1,837 | 3,221 | 388 | 7 | 49,712 |

- Q has 15 beats in total and is excluded from macro-averaged scores (N, S, V, F only).

## 3. Denoising variants (all zero-phase, applied to the MLII lead)
| Name | What it does |
|---|---|
| none | signal unchanged (control) |
| bandpass | 4th-order IIR band-pass 0.5-40 Hz plus a 60 Hz notch (58-62 Hz band-stop) |
| wavelet | MATLAB `wdenoise`, sym4 wavelet, Bayes soft thresholding |
| emd | empirical mode decomposition; an IMF is kept only if its mean frequency is in 0.5-40 Hz |
| highpass | 4th-order IIR high-pass, 0.5 Hz only (diagnostic) |
| lowpass | 4th-order IIR low-pass, 40 Hz only (diagnostic) |

The first version of the EMD variant dropped a fixed number of IMFs. It performed poorly in a
pilot detection run and was replaced by the frequency-based rule above before any
classification result was computed. Only the revised rule is used in the comparison.

## 4. R-peak detector
Pan-Tompkins-style detector, applied to the denoised signal:
1. band-pass 5-15 Hz; 2. derivative; 3. squaring; 4. moving-window integration (150 ms);
5. candidate peaks with a 200 ms refractory period; 6. adaptive signal/noise peak estimates
(threshold = NPKI + 0.25 (SPKI - NPKI)); 7. search-back with half the threshold when no beat is
found within 1.66 times the mean of the last eight RR intervals; 8. the effect of a single very
large peak on SPKI is capped at three times SPKI.
Each detection is then moved to the sample with the largest deviation from the local median
within +/-100 ms, so that the morphology window is centred on the R-peak. Detections are
matched one-to-one to annotated beats within +/-50 ms.

## 5. Detection performance (DS2, whole records, variant `none`)
- 49,712 annotated beats; 218 missed and 208 false detections.
- Sensitivity 99.56 % and positive predictivity 99.58 %.
- Across the six denoising variants the counts barely change (missed 214-237, false 204-227),
  so the choice of denoising did not affect detection. The detector's own 5-15 Hz band-pass
  already removes most of what the denoisers target **[interpretation, not tested separately]**.
- Weakest records (training set, variant `none`): 208 (444 missed, 429 false), 207 (66 missed,
  481 false) and 108 (64 missed, 341 false).
- A pilot on the first 300 s of each record gave 99.78 % / 98.51 %. That short-window figure is
  not a full-record result and should not be quoted as one.

## 6. Limitations
- The detector was developed by looking at detection scores on all 44 records, including DS2,
  so the detection figures are slightly optimistic for unseen data. The classification
  comparison does not tune anything on DS2.
- One database, one lead, 22 test patients. Which patients are in the test set is the largest
  source of uncertainty (see the bootstrap intervals in the integration report).
- The detector misses and falsely detects more beats in the training set than in the test set
  (records 207, 208, 108), which affects the detected-peak training labels.
- Filter parameters (cutoffs, filter order, wavelet, IMF rule) were fixed in advance and not
  optimised.
