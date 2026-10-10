% TRACK_A_FULL_VALIDATION  Runs the Track A chain (denoise -> detect -> validate)
% across ALL 44 records (DS1 + DS2 combined - detection validation doesn't
% care about train/test split, only classification later will).
%
% To test a different denoising variant, change ONLY the line below marked
% CHANGE THIS, then re-run. This is designed to be reused for A2, A3, A4.

denoise_fn = @denoise_none;      % <-- CHANGE THIS for A2/A3/A4 (e.g. @denoise_bandpass)
denoise_name = 'none';           % <-- CHANGE THIS to match (e.g. 'bandpass')

% --- Load the full record list from the split file (never hand-type record IDs) ---
split_info = jsondecode(fileread('data/splits/ds1_ds2_split.json'));
all_records = [split_info.ds1_training; split_info.ds2_testing];

fprintf('Running Track A validation on %d records, denoising = %s\n', ...
    numel(all_records), denoise_name);

results = table('Size', [numel(all_records), 5], ...
    'VariableTypes', {'string','double','double','double','double'}, ...
    'VariableNames', {'record_id','true_beats','detected_peaks','sensitivity','ppv'});

for i = 1:numel(all_records)
    rec_id = all_records{i};
    try
        record = load_record(rec_id);
        signal_denoised = denoise_fn(record.signal(:,1), record.fs);
        detected_peaks = detect_rpeaks_pantompkins(signal_denoised, record.fs);
        [sens, ppv] = validate_detection(detected_peaks, record.ann_samples, record.fs);

        results.record_id(i) = rec_id;
        results.true_beats(i) = numel(record.ann_samples);
        results.detected_peaks(i) = numel(detected_peaks);
        results.sensitivity(i) = sens;
        results.ppv(i) = ppv;

        fprintf('Record %-5s | true=%5d detected=%5d | sens=%.2f%% ppv=%.2f%%\n', ...
            rec_id, numel(record.ann_samples), numel(detected_peaks), sens*100, ppv*100);
    catch ME
        fprintf('Record %-5s | ERROR: %s\n', rec_id, ME.message);
        results.record_id(i) = rec_id;
        results.sensitivity(i) = NaN;
        results.ppv(i) = NaN;
    end
end

% --- Summary ---
valid = ~isnan(results.sensitivity);
fprintf('\n--- Summary (denoising = %s) ---\n', denoise_name);
fprintf('Records processed successfully: %d / %d\n', sum(valid), numel(all_records));
fprintf('Average sensitivity: %.2f%%\n', mean(results.sensitivity(valid)) * 100);
fprintf('Average positive predictivity: %.2f%%\n', mean(results.ppv(valid)) * 100);

[worst_sens, worst_idx] = min(results.sensitivity(valid));
valid_ids = results.record_id(valid);
fprintf('Worst-performing record (by sensitivity): %s (%.2f%%)\n', ...
    valid_ids(worst_idx), worst_sens * 100);

% --- Save results so you can compare denoising variants later ---
if ~exist('results', 'dir')
    mkdir('results');
end
out_filename = fullfile('results', sprintf('track_a_validation_%s.csv', denoise_name));
writetable(results, out_filename);
fprintf('\nResults saved to: %s\n', out_filename);
