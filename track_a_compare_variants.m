% TRACK_A_COMPARE_VARIANTS Stage 0: R-peak detection across 4 denoising variants

% Direct execution from pwd
script_dir = fileparts(mfilename('fullpath'));
if ~isempty(script_dir)
    cd(script_dir);
end

%% ---------------- CONFIGURATION ----------------
cfg.split_file = fullfile('data', 'splits', 'ds1_ds2_split.json');
cfg.lead_name  = 'MLII';
cfg.duration_s = 300;
cfg.out_dir    = fullfile('results', 'track_a');

variant_names = {'none', 'bandpass', 'wavelet', 'emd'};
variant_funcs = {@denoise_none, @denoise_bandpass, @denoise_wavelet, @denoise_emd};
nV = numel(variant_names);
cls_names = {'N', 'S', 'V', 'F', 'Q'};

%% ---------------- DIRECTORY SANITY CHECK ----------------
if ~isfile(cfg.split_file)
    error('Split file not found: %s. Run from D:\\Git\\Repo\\MlProject.', cfg.split_file);
end

if ~isfolder(cfg.out_dir)
    mkdir(cfg.out_dir);
end

%% ---------------- RECORD LIST FROM SPLIT JSON ----------------
split = jsondecode(fileread(cfg.split_file));
ds1   = ids_to_cellstr(split.ds1_training);
ds2   = ids_to_cellstr(split.ds2_testing);
paced = ids_to_cellstr(split.excluded_paced_patients);

assert(isempty(intersect(ds1, ds2)), 'Sanity check failed: overlap between DS1 and DS2.');
assert(isempty(intersect([ds1; ds2], paced)), 'Sanity check failed: paced record in DS1/DS2.');

record_ids = sort([ds1; ds2]);
nR = numel(record_ids);
fprintf('Records: %d (DS1 %d + DS2 %d); paced excluded: %d\n\n', ...
    nR, numel(ds1), numel(ds2), numel(paced));

%% ---------------- PREALLOCATION ----------------
nRows       = nR * nV;
col_record  = cell(nRows, 1);
col_split   = cell(nRows, 1);
col_variant = cell(nRows, 1);
col_n_all   = zeros(nRows, 1);
col_n_beat  = zeros(nRows, 1);
col_n_det   = zeros(nRows, 1);
col_s_old   = zeros(nRows, 1);
col_p_old   = zeros(nRows, 1);
col_s_new   = zeros(nRows, 1);
col_p_new   = zeros(nRows, 1);

removed_full = cell(0, 1);
removed_win  = cell(0, 1);
rec_removed_win = zeros(nR, 1);

tot = struct('all_full', 0, 'beat_full', 0, 'all_win', 0, 'beat_win', 0);
class_ds1 = zeros(1, numel(cls_names));
class_ds2 = zeros(1, numel(cls_names));

%% ---------------- MAIN LOOP ----------------
row = 0;
t0  = tic;
for r = 1:nR
    id  = record_ids{r};
    rec = load_record_by_id(id);
    
    lead_idx = find(strcmp(rec.lead_names, cfg.lead_name), 1);
    if isempty(lead_idx)
        error('Record %s has no %s lead.', id, cfg.lead_name);
    end
    
    fs    = rec.fs;
    n_win = min(size(rec.signal, 1), round(cfg.duration_s * fs));
    x     = rec.signal(1:n_win, lead_idx);
    
    % Ground truth annotations
    [beat_samples, ~, ~, info] = get_beat_annotations(rec);
    all_ann = double(rec.ann_samples(:));
    in_win  = all_ann <= n_win;
    gt_old  = all_ann(in_win);
    gt_new  = beat_samples(beat_samples <= n_win);
    
    removed_full = [removed_full; info.all_symbols(~info.is_beat)];          %#ok<AGROW>
    removed_win  = [removed_win;  info.all_symbols(~info.is_beat & in_win)]; %#ok<AGROW>
    rec_removed_win(r) = sum(~info.is_beat & in_win);
    
    tot.all_full  = tot.all_full  + info.n_total;
    tot.beat_full = tot.beat_full + info.n_beats;
    tot.all_win   = tot.all_win   + numel(gt_old);
    tot.beat_win  = tot.beat_win  + numel(gt_new);
    
    cc = cellfun(@(c) info.class_counts.(c), cls_names);
    if ismember(id, ds1)
        split_label = 'DS1';
        class_ds1   = class_ds1 + cc;
    else
        split_label = 'DS2';
        class_ds2   = class_ds2 + cc;
    end
    
    for v = 1:nV
        y   = variant_funcs{v}(x, fs);
        det = detect_rpeaks_pantompkins(y, fs);
        det = double(det(:));
        
        [s_old, p_old] = validate_detection(det, gt_old, fs);
        [s_new, p_new] = validate_detection(det, gt_new, fs);
        
        row = row + 1;
        col_record{row}  = id;
        col_split{row}   = split_label;
        col_variant{row} = variant_names{v};
        col_n_all(row)   = numel(gt_old);
        col_n_beat(row)  = numel(gt_new);
        col_n_det(row)   = numel(det);
        col_s_old(row)   = s_old;
        col_p_old(row)   = p_old;
        col_s_new(row)   = s_new;
        col_p_new(row)   = p_new;
    end
    
    fprintf('[%2d/%d] %s  annotations(300s)=%4d  beats(300s)=%4d  removed(300s)=%3d   %5.0f s elapsed\n', ...
        r, nR, id, numel(gt_old), numel(gt_new), rec_removed_win(r), toc(t0));
end

%% ---------------- PERCENT SCALING ----------------
all_metrics = [col_s_old; col_p_old; col_s_new; col_p_new];
if max(all_metrics) <= 1
    col_s_old = 100 * col_s_old;   col_p_old = 100 * col_p_old;
    col_s_new = 100 * col_s_new;   col_p_new = 100 * col_p_new;
end

%% ---------------- SAVE PER-RECORD TABLE ----------------
T = table(col_record, col_split, col_variant, col_n_all, col_n_beat, col_n_det, ...
          col_s_old, col_p_old, col_s_new, col_p_new, ...
    'VariableNames', {'record', 'split', 'variant', 'n_annotations_all', 'n_beats', ...
                      'n_detected', 'sens_old_pct', 'ppv_old_pct', 'sens_new_pct', 'ppv_new_pct'});
writetable(T, fullfile(cfg.out_dir, 'stage0_detection_per_record.csv'));

%% ---------------- REMOVED-SYMBOL TABLE ----------------
if isempty(removed_full)
    usym = cell(0, 1);  cnt_full = zeros(0, 1);  cnt_win = zeros(0, 1);
else
    [usym, ~, ic] = unique(removed_full);
    usym     = usym(:);
    cnt_full = accumarray(ic(:), 1, [numel(usym), 1]);
    cnt_win  = cellfun(@(s) sum(strcmp(removed_win, s)), usym);
end
R = table(usym, cnt_full, cnt_win, ...
    'VariableNames', {'symbol', 'count_whole_record', 'count_first_300s'});
writetable(R, fullfile(cfg.out_dir, 'stage0_removed_nonbeats.csv'));

%% ---------------- SUMMARY REPORT ----------------
summary_file = fullfile(cfg.out_dir, 'stage0_summary.txt');
if isfile(summary_file)
    delete(summary_file);
end

diary(summary_file);
fprintf('\n==================== PASTE FROM HERE ====================\n');
fprintf('MATLAB %s\n', version);
fprintf('Records: %d (DS1 %d, DS2 %d), lead %s, first %d s\n\n', ...
    nR, numel(ds1), numel(ds2), cfg.lead_name, cfg.duration_s);

fprintf('-- Annotation cleanup --\n');
fprintf('Whole records : %6d annotations -> %6d beats, %5d non-beats removed\n', ...
    tot.all_full, tot.beat_full, tot.all_full - tot.beat_full);
fprintf('First %3d s   : %6d annotations -> %6d beats, %5d non-beats removed\n\n', ...
    cfg.duration_s, tot.all_win, tot.beat_win, tot.all_win - tot.beat_win);

fprintf('Removed symbols    whole   first300s\n');
for k = 1:numel(usym)
    fprintf('   ''%s''         %7d   %7d\n', usym{k}, cnt_full(k), cnt_win(k));
end

[~, ord] = sort(rec_removed_win, 'descend');
fprintf('\nMost non-beats removed in first %d s: ', cfg.duration_s);
for k = 1:min(5, nR)
    fprintf('%s (%d)  ', record_ids{ord(k)}, rec_removed_win(ord(k)));
end
fprintf('\n\n');

fprintf('-- Beats per AAMI class (whole records) --\n');
fprintf('        %8s %8s %8s %8s %8s %9s\n', cls_names{:}, 'total');
fprintf('DS1     %8d %8d %8d %8d %8d %9d\n', class_ds1, sum(class_ds1));
fprintf('DS2     %8d %8d %8d %8d %8d %9d\n\n', class_ds2, sum(class_ds2));

fprintf('-- Detection, mean over %d records (percent) --\n', nR);
fprintf('variant    sens_OLD  ppv_OLD   sens_NEW  ppv_NEW   min_sens_NEW  min_ppv_NEW\n');
for v = 1:nV
    m = strcmp(T.variant, variant_names{v});
    fprintf('%-9s  %7.2f   %7.2f   %7.2f   %7.2f   %10.2f   %10.2f\n', variant_names{v}, ...
        mean(T.sens_old_pct(m), 'omitnan'), mean(T.ppv_old_pct(m), 'omitnan'), ...
        mean(T.sens_new_pct(m), 'omitnan'), mean(T.ppv_new_pct(m), 'omitnan'), ...
        min(T.sens_new_pct(m)), min(T.ppv_new_pct(m)));
end

fprintf('\n-- 5 hardest records per variant (NEW ground truth, by mean of sens and PPV) --\n');
for v = 1:nV
    m   = find(strcmp(T.variant, variant_names{v}));
    sc  = (T.sens_new_pct(m) + T.ppv_new_pct(m)) / 2;
    [~, o] = sort(sc, 'ascend');
    fprintf('%-9s ', variant_names{v});
    for k = 1:min(5, numel(o))
        i = m(o(k));
        fprintf(' %s(S%.1f/P%.1f)', T.record{i}, T.sens_new_pct(i), T.ppv_new_pct(i));
    end
    fprintf('\n');
end

n_nan = sum(isnan([T.sens_new_pct; T.ppv_new_pct]));
fprintf('\nSanity: NaN metrics = %d, DS1/DS2 overlap = %d, rows = %d (expected %d)\n', ...
    n_nan, numel(intersect(ds1, ds2)), height(T), nR * nV);
fprintf('===================== PASTE TO HERE =====================\n');
diary off;

%% ======================= LOCAL FUNCTIONS =======================
function c = ids_to_cellstr(x)
if isnumeric(x)
    c = arrayfun(@(v) sprintf('%d', v), x(:), 'UniformOutput', false);
elseif isstring(x)
    c = cellstr(x(:));
elseif ischar(x)
    c = cellstr(x);
elseif iscellstr(x)
    c = x(:);
else
    c = cellfun(@(v) char(string(v)), x(:), 'UniformOutput', false);
end
c = strtrim(c(:));
end

function rec = load_record_by_id(id)
try
    rec = load_record(id);
catch err_text
    try
        rec = load_record(str2double(id));
    catch
        rethrow(err_text);
    end
end
end