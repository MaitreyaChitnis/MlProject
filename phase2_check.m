% PHASE2_CHECK  Sanity-check for extract_features.m on one record.
% Run from the project root (Current Folder = folder containing data/ and src/).

addpath(genpath('src'));

record = load_record('100');
[X, y, idx] = extract_features(record);

fprintf('Annotations in file : %d (includes non-beat ones like "+")\n', numel(record.ann_samples));
fprintf('Feature matrix size : %d beats x %d columns (expect 184 columns)\n', size(X,1), size(X,2));
fprintf('Label vector length : %d (must equal number of rows)\n', numel(y));
fprintf('Any NaN in features : %d (expect 0)\n', any(isnan(X(:))));

fprintf('\nClass counts:\n');
for c = 'NSVFQ'
    fprintf('  %c : %d\n', c, sum(y == c));
end

fprintf('\nMean RR_prev = %.3f s, RR_next = %.3f s, RR_local_avg = %.3f s\n', ...
    mean(X(:,1)), mean(X(:,2)), mean(X(:,3)));
fprintf('(for record 100 these should all be roughly 0.8 s)\n');

% Alignment check: is the annotated sample the local max of |signal|,
% or is the true peak 1 sample later (0-based vs 1-based indexing issue)?
sig = record.signal(:,1);
sig = sig - median(sig);
n = min(500, numel(idx));
at0 = 0; at1 = 0;
for k = 1:n
    r = idx(k);
    win = abs(sig(r-3:r+3));
    [~, m] = max(win);
    off = m - 4; % -3..+3 relative to annotated sample
    if off == 0, at0 = at0 + 1; end
    if off == 1, at1 = at1 + 1; end
end
fprintf('\nPeak alignment over %d beats: exactly on annotation = %d, one sample later = %d\n', n, at0, at1);
fprintf('If "one sample later" is clearly larger, add ann_samples = ann_samples + 1; to read_mitbih_annotations.m\n');

% Plot one beat's morphology window
figure;
plot(-90:90, X(10, 4:end));
xlabel('Samples relative to R-peak'); ylabel('Amplitude');
title(sprintf('Morphology window of beat 10 (label %c)', y(10)));
