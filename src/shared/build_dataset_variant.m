function ds = build_dataset_variant(ids, variant_fn, peak_source, opts)
%BUILD_DATASET_VARIANT  Feature matrix for ONE denoising variant and ONE peak source.
%
%   ds = build_dataset_variant(ids, @denoise_wavelet, 'detected')
%   ds = build_dataset_variant(ids, @denoise_none,    'groundtruth', opts)
%
%   ids          cell array of record IDs (from load_split - never typed by hand)
%   variant_fn   handle: denoised = fn(signal, fs)   (e.g. @denoise_emd)
%   peak_source  'groundtruth' : R-peaks = annotated beats (as in phase3_build)
%                'detected'    : R-peaks = detect_rpeaks_pantompkins on the DENOISED
%                                signal, refined to the local signal extremum, then
%                                labelled by matching to the nearest true beat
%                                (+/- 50 ms, one-to-one).
%   opts         optional struct (defaults in brackets):
%                  data_dir   ['data/raw']      lead_name ['MLII']
%                  duration_s [Inf = whole record]
%                  half_window [90]   n_avg [10]   (same as extract_features)
%                  match_ms [50]  refine_ms [100]
%
%   OUTPUT struct ds:
%     .X .y .row_record .record_ids    same layout as build_datasets.m
%     .stats   table per record: n_true_beats, n_detections, n_matched,
%              n_false_pos, n_missed, n_rows, median_offset_samples
%     .opts    the options actually used
%
%   HOW DETECTED PEAKS ARE HANDLED (nothing is hidden)
%     * RR intervals are computed from ALL detections, including false ones,
%       exactly as a real system would see them.
%     * Detections that match no true beat have no label, so their rows are
%       dropped from X/y AFTER the features are computed. They are counted in
%       n_false_pos. True beats the detector missed are counted in n_missed.
%     * Peak positions are refined to the largest deviation from the local
%       median within +/- refine_ms, because the detector's integrated-signal
%       peak sits a few samples away from the true R-peak and the morphology
%       window must be centred on the R-peak.
%
%   Uses extract_features.m, get_beat_annotations.m and map_symbol_to_aami.m
%   UNCHANGED (extract_features is given a stand-in record holding the
%   denoised signal and the chosen peaks).

    if nargin < 4 || isempty(opts), opts = struct(); end
    opts = fill_defaults(opts);

    peak_source = lower(peak_source);
    if ~any(strcmp(peak_source, {'groundtruth', 'detected'}))
        error('build_dataset_variant:badSource', ...
            'peak_source must be ''groundtruth'' or ''detected'' (got ''%s'').', peak_source);
    end

    nR = numel(ids);
    Xc = cell(nR, 1);  yc = cell(nR, 1);  rc = cell(nR, 1);
    st = zeros(nR, 7);

    for k = 1:nR
        id  = ids{k};
        rec = load_record(id, opts.data_dir);

        lead = find(strcmpi(strtrim(rec.lead_names), opts.lead_name), 1);
        if isempty(lead)
            error('build_dataset_variant:noLead', 'Record %s has no %s lead.', id, opts.lead_name);
        end
        fs   = rec.fs;
        nUse = size(rec.signal, 1);
        if isfinite(opts.duration_s)
            nUse = min(nUse, round(opts.duration_s * fs));
        end

        x = rec.signal(1:nUse, lead);
        y = variant_fn(x, fs);
        y = y(:);
        if numel(y) ~= nUse
            error('build_dataset_variant:badLength', ...
                'Record %s: denoiser returned %d samples, expected %d.', id, numel(y), nUse);
        end

        [gt_s, ~, gt_sym] = get_beat_annotations(rec);
        in_range = gt_s >= 1 & gt_s <= nUse;
        gt_s   = gt_s(in_range);
        gt_sym = gt_sym(in_range);

        if strcmp(peak_source, 'groundtruth')
            locs    = gt_s;
            syms    = gt_sym;
            is_real = true(numel(locs), 1);
            n_match = numel(locs);
            med_off = 0;
        else
            det = double(detect_rpeaks_pantompkins(y, fs));
            det = det(:);
            det = refine_peaks(y, det, round(opts.refine_ms / 1000 * fs));

            mi      = match_to_truth(det, gt_s, round(opts.match_ms / 1000 * fs));
            is_real = mi > 0;
            syms    = repmat({'N'}, numel(det), 1);   % placeholder for unmatched detections
            syms(is_real) = gt_sym(mi(is_real));
            locs    = det;
            n_match = sum(is_real);
            if n_match > 0
                med_off = median(abs(det(is_real) - gt_s(mi(is_real))));
            else
                med_off = NaN;
            end
        end

        % extract_features expects a record: signal, fs, ann_samples, ann_symbols
        rec2 = struct('signal', y, 'fs', fs, 'ann_samples', locs, 'ann_symbols', {syms});
        [X, lab, bs] = extract_features(rec2, 1, opts.half_window, opts.n_avg);

        % drop rows that belong to unmatched (false) detections
        [tf, pos] = ismember(bs, locs);
        if ~all(tf)
            error('build_dataset_variant:internal', 'Record %s: beat sample not found in peak list.', id);
        end
        keep = is_real(pos);
        X = X(keep, :);
        lab = lab(keep);

        Xc{k} = X;
        yc{k} = lab;
        rc{k} = k * ones(size(X, 1), 1);
        st(k, :) = [numel(gt_s), numel(locs), n_match, numel(locs) - n_match, ...
                    numel(gt_s) - n_match, size(X, 1), med_off];
        fprintf('  %-12s %-8s rec %-4s : %5d rows | true %5d det %5d matched %5d\n', ...
            peak_source, func2str(variant_fn), id, size(X, 1), numel(gt_s), numel(locs), n_match);
    end

    ds.X          = vertcat(Xc{:});
    ds.y          = vertcat(yc{:});
    ds.row_record = vertcat(rc{:});
    ds.record_ids = ids(:);
    ds.stats      = array2table(st, 'VariableNames', ...
        {'n_true_beats', 'n_detections', 'n_matched', 'n_false_pos', 'n_missed', ...
         'n_rows', 'median_offset_samples'});
    ds.stats.record = ids(:);
    ds.opts       = opts;
end

%% ====================== local functions ======================
function opts = fill_defaults(opts)
    d.data_dir    = fullfile('data', 'raw');
    d.lead_name   = 'MLII';
    d.duration_s  = Inf;
    d.half_window = 90;
    d.n_avg       = 10;
    d.match_ms    = 50;
    d.refine_ms   = 100;
    f = fieldnames(d);
    for i = 1:numel(f)
        if ~isfield(opts, f{i}) || isempty(opts.(f{i}))
            opts.(f{i}) = d.(f{i});
        end
    end
end

function out = refine_peaks(y, det, w)
% Move each detection to the sample with the largest deviation from the
% local median within +/- w samples (works for upright and inverted QRS).
    n   = numel(y);
    out = zeros(size(det));
    for i = 1:numel(det)
        a = max(1, det(i) - w);
        b = min(n, det(i) + w);
        seg = y(a:b);
        [~, m] = max(abs(seg - median(seg)));
        out(i) = a + m - 1;
    end
    out = unique(out);   % sorted, duplicates removed
end

function mi = match_to_truth(det, gt, tol)
% One-to-one matching: each detection -> nearest true beat within tol samples.
% If several detections claim the same true beat, only the closest keeps it.
    nD = numel(det);  nG = numel(gt);
    mi = zeros(nD, 1);
    if nD == 0 || nG == 0, return; end
    nearest = zeros(nD, 1);  dist = zeros(nD, 1);
    for i = 1:nD
        [dist(i), nearest(i)] = min(abs(gt - det(i)));
    end
    [~, ord] = sort(dist);
    used = false(nG, 1);
    for t = 1:nD
        i = ord(t);
        if dist(i) <= tol && ~used(nearest(i))
            mi(i) = nearest(i);
            used(nearest(i)) = true;
        end
    end
end
