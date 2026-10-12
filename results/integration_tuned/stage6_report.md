# Stage 6 Report: Denoising Variant Comparison under the Tuned Random Forest Model

## 1. Summary Tables

### A) Per-Variant Metrics (Ground Truth Source, Tuned Model)
| Variant | Accuracy (%) | Macro-F1 [95% CI] | S Sensitivity (%) | S Precision (%) | S-Class F1 | V-Class F1 | Missed Peaks | False Detections |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **none** | 88.78 | 0.467 [0.405, 0.553] | 8.3 | 22.4 | 0.120 | 0.791 | 0 | 0 |
| **bandpass** | 82.92 | 0.419 [0.334, 0.527] | 13.4 | 22.2 | 0.167 | 0.603 | 0 | 0 |
| **wavelet** | 88.34 | 0.457 [0.390, 0.543] | 7.9 | 24.9 | 0.120 | 0.760 | 0 | 0 |
| **emd** | 85.42 | 0.419 [0.336, 0.524] | 10.7 | 24.4 | 0.148 | 0.606 | 0 | 0 |
| **highpass** | 83.32 | 0.421 [0.334, 0.536] | 12.8 | 23.7 | 0.166 | 0.610 | 0 | 0 |
| **lowpass** | 88.07 | 0.459 [0.393, 0.543] | 8.4 | 19.6 | 0.116 | 0.774 | 0 | 0 |

### B) True S-Beat Destination for the 'none' Variant
Total true S beats in DS2: **1,836**
* **True S $\rightarrow$ Predicted N:** 1,635 beats (89.1%)
* **True S $\rightarrow$ Predicted S:** 158 beats (8.6%)
* **True S $\rightarrow$ Predicted V:** 34 beats (1.9%)
* **True S $\rightarrow$ Predicted F:** 9 beats (0.5%)
* **True S $\rightarrow$ Predicted Q:** 0 beats (0.0%)

---

## 2. Evaluation Questions & Findings

* **Does the model now learn S, and at what cost to N/V accuracy?**
  * **Answer:** **Not supported** (for effective learning) / Partially supported for minor sensitivity shift.
  * **Details:** While sensitivity for class S improved slightly compared to the baseline model (rising from 1–2.7% to ~8.3% for the 'none' variant), S performance remains extremely poor (S-class F1 = 0.120). The vast majority of true S beats (89.1%) are still misclassified as normal (N). Meanwhile, overall accuracy sits at 88.78% and V-class F1 remains high (0.791), indicating that N and V recognition are preserved but S remains largely unlearned.

* **Do the denoising conclusions (wavelet/lowpass neutral; bandpass/highpass/emd lower V-F1) still hold under the tuned model?**
  * **Answer:** **Supported**.
  * **Details:** Wavelet and lowpass variants show negligible differences from 'none' (paired bootstrap 95% CIs for macro-F1 and V-F1 include zero). Conversely, bandpass, highpass, and EMD substantially lower V-class F1 (e.g., EMD V-F1 drops to 0.606 vs 0.791 for 'none', with the EMD vs. none difference CI excluding zero).

* **Is any S-class difference between variants outside the 95% interval?**
  * **Answer:** **Not supported**.
  * **Details:** None of the paired bootstrap 95% confidence intervals for S-class F1 differences between filtered variants and the 'none' variant exclude zero (all CIs cross zero).

* **Is S performance concentrated in a few patients?**
  * **Answer:** **Supported**.
  * **Details:** True S beats are heavily skewed across the 22 DS2 patients. Patient 232 alone holds 75.2% of all true S beats (1,381 out of 1,836), and the top 3 patients (232, 222, and 202) account for 89.6% of all true S beats. Performance is thus dominated by patient-specific pathology distribution.

---

## 3. Methodological Caveats & Limitations
* **Test Population Size:** Evaluations are restricted to only 22 test patients in DS2.
* **Tuning Generalizability:** 3-fold cross-validation over 22 patients in Phase 5 is a weak empirical basis for selecting hyperparameters, leading to a Uniform prior with MinLeafSize=5 that prioritizes majority class stability over rare-class discovery.
* **Unverified Assumptions:** No noise-stress tests or external datasets were evaluated beyond the specified DS1/DS2 split.