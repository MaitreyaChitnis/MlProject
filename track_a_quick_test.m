% TRACK_A_QUICK_TEST  First end-to-end test of the Track A chain:
% load -> denoise (none) -> detect R-peaks -> validate against ground truth.
% Run this on one record first before scaling to all 44.

record = load_record('100');

% --- A1: baseline passthrough (no denoising) ---
% Using lead 1 (first column) - MLII, the standard lead for QRS detection
signal_denoised = denoise_none(record.signal(:,1), record.fs);

% --- A5: Pan-Tompkins R-peak detection ---
detected_peaks = detect_rpeaks_pantompkins(signal_denoised, record.fs);

% --- A6: validate against ground truth ---
[sensitivity, positive_predictivity] = validate_detection(detected_peaks, record.ann_samples, record.fs);

fprintf('--- Track A quick test: record 100, denoising = none ---\n');
fprintf('Ground-truth beats: %d\n', numel(record.ann_samples));
fprintf('Detected peaks:     %d\n', numel(detected_peaks));
fprintf('Sensitivity:          %.2f%%\n', sensitivity * 100);
fprintf('Positive predictivity: %.2f%%\n', positive_predictivity * 100);

% Visual check: plot first 10 seconds with both ground truth and detected peaks
fs = record.fs;
window_samples = 10 * fs;
sig = signal_denoised(1:window_samples);

figure;
plot(sig); hold on;

true_in_range = record.ann_samples(record.ann_samples <= window_samples);
plot(true_in_range, sig(true_in_range), 'go', 'MarkerSize', 10, 'LineWidth', 1.5);

det_in_range = detected_peaks(detected_peaks <= window_samples);
plot(det_in_range, sig(det_in_range), 'rx', 'MarkerSize', 10, 'LineWidth', 1.5);

xlabel('Sample number'); ylabel('Amplitude');
title('Record 100 (first 10s): ground truth (green o) vs detected (red x)');
legend('Signal', 'Ground-truth R-peak', 'Detected R-peak');
hold off;
