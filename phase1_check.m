% PHASE1_CHECK  Sanity-check script: loads one record, prints basic info,
% plots the first 10 seconds with annotated R-peaks overlaid.
%
% Run this from the MATLAB "Run" button (green triangle) after setting
% your Current Folder to the project root.

record = load_record('100');

fprintf('Record ID: %s\n', record.id);
fprintf('Sampling frequency: %d Hz\n', record.fs);
fprintf('Signal length: %d samples (%.1f minutes)\n', ...
    size(record.signal,1), size(record.signal,1)/record.fs/60);
fprintf('Number of annotated beats: %d\n', numel(record.ann_samples));

% Plot first 10 seconds with R-peaks marked
fs = record.fs;
window_samples = 10 * fs;
sig = record.signal(1:window_samples, 1);

figure;
plot(sig);
hold on;

peaks_in_range = record.ann_samples(record.ann_samples <= window_samples);
plot(peaks_in_range, record.signal(peaks_in_range,1), 'ro', 'MarkerSize', 8, 'LineWidth', 1.5);

xlabel('Sample number');
ylabel('Amplitude');
title('First 10 seconds of record 100, with annotated R-peaks');
legend('ECG signal', 'Annotated R-peak');
hold off;
