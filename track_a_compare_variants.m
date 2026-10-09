% TRACK_A_COMPARE_VARIANTS  Runs ALL four denoising variants through the same
% detector across all 44 records and builds the comparison table (Gap 1).
% Always uses the MLII lead (picked by name; record 114 has leads swapped).
%
% SETTINGS you may change:
max_seconds = 300;   % analyse only the first N seconds of every record, for ALL
                     % variants equally (keeps EMD fast). Use Inf for full records.

variants = { 'none',     @denoise_none;
             'bandpass', @denoise_bandpass;
             'wavelet',  @denoise_wavelet;
             'emd',      @denoise_emd };

split_info = jsondecode(fileread('data/splits/ds1_ds2_split.json'));
all_records = [split_info.ds1_training; split_info.ds2_testing];
if ~exist('results','dir'), mkdir('results'); end

summary = table('Size',[size(variants,1) 6], ...
    'VariableTypes',{'string','double','double','double','string','double'}, ...
    'VariableNames',{'variant','mean_sens','mean_ppv','min_sens','worst_record','minutes'});

for v = 1:size(variants,1)
    name = variants{v,1};
    fn   = variants{v,2};
    fprintf('\n=== Variant: %s ===\n', name);
    t0 = tic;

    res = table('Size',[numel(all_records) 5], ...
        'VariableTypes',{'string','double','double','double','double'}, ...
        'VariableNames',{'record_id','true_beats','detected_peaks','sensitivity','ppv'});

    for i = 1:numel(all_records)
        rec_id = all_records{i};
        res.record_id(i) = rec_id;
        try
            record = load_record(rec_id);
            lead = find(strcmp(record.lead_names, 'MLII'), 1);
            if isempty(lead), lead = 1; end

            N = min(size(record.signal,1), round(max_seconds * record.fs));
            sig = record.signal(1:N, lead);
            truth = record.ann_samples(record.ann_samples <= N);

            sig_dn = fn(sig, record.fs);
            det = detect_rpeaks_pantompkins(sig_dn, record.fs);
            [sens, ppv] = validate_detection(det, truth, record.fs);

            res.true_beats(i) = numel(truth);
            res.detected_peaks(i) = numel(det);
            res.sensitivity(i) = sens;
            res.ppv(i) = ppv;
            fprintf('%-8s rec %-4s sens=%.2f%% ppv=%.2f%%\n', name, rec_id, sens*100, ppv*100);
        catch ME
            fprintf('%-8s rec %-4s ERROR: %s\n', name, rec_id, ME.message);
            res.sensitivity(i) = NaN; res.ppv(i) = NaN;
        end
    end

    writetable(res, fullfile('results', sprintf('track_a_validation_%s.csv', name)));
    ok = ~isnan(res.sensitivity);
    [mn, idx] = min(res.sensitivity(ok));
    ids = res.record_id(ok);
    summary.variant(v)      = name;
    summary.mean_sens(v)    = mean(res.sensitivity(ok))*100;
    summary.mean_ppv(v)     = mean(res.ppv(ok))*100;
    summary.min_sens(v)     = mn*100;
    summary.worst_record(v) = ids(idx);
    summary.minutes(v)      = toc(t0)/60;
end

fprintf('\n===== DENOISING COMPARISON (first %g s of each record, MLII lead) =====\n', max_seconds);
disp(summary);
writetable(summary, fullfile('results','track_a_variant_comparison.csv'));
fprintf('Saved: results\\track_a_variant_comparison.csv\n');
