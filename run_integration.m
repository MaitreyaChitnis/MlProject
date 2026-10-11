%RUN_INTEGRATION  Does the denoising method change the FINAL classification result?
%
%  Run from the repo root (D:\Git\Repo\MlProject):
%      run_integration
%
%  WHAT IT DOES
%   For each denoising variant (none / bandpass / wavelet / emd) and each
%   peak source (groundtruth / detected):
%     1. builds the DS1 (train) and DS2 (test) feature matrices with
%        build_dataset_variant.m  (cached in data/processed/variants/)
%     2. trains the SAME Random Forest (same settings, same seeds) on DS1
%     3. tests it ONCE on DS2 - nothing is tuned on DS2
%   Then it reports per-class results, macro-F1 (N,S,V,F) and patient-level
%   bootstrap confidence intervals (DS2 records are resampled, not beats),
%   including the paired difference of every variant against 'none'.
%
%  Only the denoising step differs between variants. Record lists come from
%  data/splits/ds1_ds2_split.json via load_split.m.
%
%  OUTPUTS (results/integration/)
%    integration_summary.csv      one row per source x variant
%    integration_vs_none.csv      paired bootstrap differences vs 'none'
%    integration_figure.png       macro-F1 and S-class F1 by variant
%    integration_summary.txt      console summary (paste this)
%
%  RUNTIME: dataset building is slow the first time (EMD especially) and each
%  forest takes a few minutes. Start with cfg.n_seeds = 1 to test quickly.

clear; clc;
addpath(genpath('src'));
t_start = tic;

%% ---------------- settings you may edit ----------------
cfg.variant_names = {'none', 'bandpass', 'wavelet', 'emd'};
cfg.variant_funcs = {@denoise_none, @denoise_bandpass, @denoise_wavelet, @denoise_emd};
cfg.sources       = {'groundtruth', 'detected'};
cfg.n_seeds       = 3;       % forests per combination (different seeds). Use 1 for a quick test
cfg.n_boot        = 2000;    % patient-level bootstrap resamples
cfg.use_tuned_config = true; % use the phase-5 settings if data/processed/tuned_rf.mat exists
cfg.rebuild       = false;   % true = ignore cached datasets and rebuild
cfg.use_parallel  = false;   % true needs the Parallel Computing Toolbox
cfg.ds_opts       = struct('duration_s', Inf, 'half_window', 90, 'n_avg', 10, ...
                           'match_ms', 50, 'refine_ms', 100);
cfg.diagnostic_variants = true;  % adds 'highpass' (0.5 Hz only) and 'lowpass' (40 Hz only)
cfg.prior_override = '';         % '' = keep model settings below; or 'empirical' | 'sqrt' | 'uniform'
cfg.leaf_override  = [];         % [] = keep; or a number such as 5
cfg.out_dir       = fullfile('results', 'integration');
cfg.cache_dir     = fullfile('data', 'processed', 'variants');
% -------------------------------------------------------

if cfg.diagnostic_variants
    cfg.variant_names = [cfg.variant_names, {'highpass', 'lowpass'}];
    cfg.variant_funcs = [cfg.variant_funcs, {@denoise_highpass, @denoise_lowpass}];
end

classes = 'NSVFQ';
nC      = numel(classes);
if ~isfolder(cfg.out_dir),   mkdir(cfg.out_dir);   end
if ~isfolder(cfg.cache_dir), mkdir(cfg.cache_dir); end

summary_file = fullfile(cfg.out_dir, 'integration_summary.txt');
if isfile(summary_file), delete(summary_file); end

par_args = {};
if cfg.use_parallel
    par_args = {'Options', statset('UseParallel', true)};
end

%% ---------------- model settings (identical for every variant) ----------------
model.name    = 'baseline (empirical prior, leaf 1)';
model.prior   = 'empirical';
model.leaf    = 1;
model.n_trees = 100;
tuned_file = fullfile('data', 'processed', 'tuned_rf.mat');
if cfg.use_tuned_config
    if isfile(tuned_file)
        T = load(tuned_file, 'results');
        model.name    = ['tuned: ' T.results.config.name];
        model.prior   = T.results.config.prior;
        model.leaf    = T.results.config.leaf;
        model.n_trees = T.results.n_trees;
    else
        warning('run_integration:noTuned', ...
            ['%s not found - using the BASELINE settings instead.\n' ...
             'Run phase5_tuning.m first if you want the tuned settings.'], tuned_file);
    end
end
if ~isempty(cfg.prior_override)
    model.prior = cfg.prior_override;
    model.name  = ['override prior = ' cfg.prior_override];
end
if ~isempty(cfg.leaf_override)
    model.leaf = cfg.leaf_override;
    model.name = [model.name ', leaf ' num2str(cfg.leaf_override)];
end
fprintf('Model for ALL variants: %s | prior=%s, MinLeafSize=%d, trees=%d, seeds=%d\n\n', ...
    model.name, model.prior, model.leaf, model.n_trees, cfg.n_seeds);

%% ---------------- record lists (from the split JSON only) ----------------
[ds1_ids, ds2_ids] = load_split();
assert(isempty(intersect(ds1_ids, ds2_ids)), 'LEAKAGE: a record is in both DS1 and DS2.');

nS = numel(cfg.sources);
nV = numel(cfg.variant_names);
nCombo = nS * nV;
R = struct('source', {}, 'variant', {}, 'n_train', {}, 'n_test', {}, 'acc', {}, ...
           'macro', {}, 'sens', {}, 'ppv', {}, 'f1', {}, 'percm', {}, ...
           'te_stats', {}, 'test_counts', {});

%% ---------------- main loop ----------------
c = 0;
for s = 1:nS
    for v = 1:nV
        c = c + 1;
        src   = cfg.sources{s};
        vname = cfg.variant_names{v};
        fprintf('\n################ [%d/%d] source = %s | variant = %s ################\n', ...
            c, nCombo, src, vname);

        tr = get_dataset('train', ds1_ds2_pick(ds1_ids), src, vname, cfg.variant_funcs{v}, cfg);
        te = get_dataset('test',  ds1_ds2_pick(ds2_ids), src, vname, cfg.variant_funcs{v}, cfg);

        assert(isempty(intersect(tr.record_ids, te.record_ids)), 'LEAKAGE between train and test records.');
        assert(~any(isnan(tr.X(:))) && ~any(isnan(te.X(:))), 'NaN found in features (%s, %s).', src, vname);

        Xtr = tr.X;  Ytr = cellstr(tr.y(:));
        Xte = te.X;  Yte = te.y(:);
        [~, ti] = ismember(Yte, classes);
        nRec2 = numel(te.record_ids);

        fprintf('DS1: %d beats | DS2: %d beats | DS2 counts N=%d S=%d V=%d F=%d Q=%d\n', ...
            size(Xtr, 1), size(Xte, 1), sum(Yte == 'N'), sum(Yte == 'S'), sum(Yte == 'V'), ...
            sum(Yte == 'F'), sum(Yte == 'Q'));

        R(c).source = src;  R(c).variant = vname;
        R(c).n_train = size(Xtr, 1);  R(c).n_test = size(Xte, 1);
        R(c).acc   = zeros(cfg.n_seeds, 1);
        R(c).macro = zeros(cfg.n_seeds, 1);
        R(c).sens  = zeros(cfg.n_seeds, nC);
        R(c).ppv   = zeros(cfg.n_seeds, nC);
        R(c).f1    = zeros(cfg.n_seeds, nC);
        R(c).percm = zeros(nC, nC, nRec2);
        R(c).test_counts = arrayfun(@(k) sum(Yte == classes(k)), 1:nC);
        R(c).te_stats = [sum(te.stats.n_true_beats), sum(te.stats.n_detections), ...
                         sum(te.stats.n_matched), sum(te.stats.n_false_pos), ...
                         sum(te.stats.n_missed), mean(te.stats.median_offset_samples, 'omitnan')];

        for sd = 1:cfg.n_seeds
            rng(sd);
            fprintf('  seed %d: training forest, about 1-2 min, nothing prints until it is done ...\n', sd);
            tic;
            mdl = TreeBagger(model.n_trees, Xtr, Ytr, ...
                'Prior', make_prior(Ytr, model.prior), ...
                'MinLeafSize', model.leaf, par_args{:});
            pred = char(predict(mdl, Xte));
            clear mdl;

            [~, pj] = ismember(pred, classes);
            cm = accumarray([ti pj], 1, [nC nC]);
            R(c).percm = R(c).percm + accumarray([ti pj te.row_record], 1, [nC nC nRec2]) / cfg.n_seeds;

            m = metrics_from_cm(cm);
            R(c).acc(sd)     = m.acc;
            R(c).macro(sd)   = m.macro_f1;
            R(c).sens(sd, :) = m.sens';
            R(c).ppv(sd, :)  = m.ppv';
            R(c).f1(sd, :)   = m.f1';
            fprintf('  seed %d: accuracy %.2f %% | macro-F1 %.3f | S sens %.1f %% | trained+tested in %.0f s\n', ...
                sd, 100 * m.acc, m.macro_f1, 100 * m.sens(2), toc);
        end
    end
end

%% ---------------- patient-level bootstrap on DS2 ----------------
nRec2 = size(R(1).percm, 3);
rng(12345);
idxB = randi(nRec2, nRec2, cfg.n_boot);     % SAME resampled patients for every combination
macroB = zeros(cfg.n_boot, nCombo);
sF1B   = zeros(cfg.n_boot, nCombo);
vF1B   = zeros(cfg.n_boot, nCombo);
for c = 1:nCombo
    for b = 1:cfg.n_boot
        m = metrics_from_cm(sum(R(c).percm(:, :, idxB(:, b)), 3));
        macroB(b, c) = m.macro_f1;
        sF1B(b, c)   = m.f1(2);
        vF1B(b, c)   = m.f1(3);
    end
end

%% ---------------- summary table ----------------
src_col = cell(nCombo, 1);  var_col = cell(nCombo, 1);
M = zeros(nCombo, 19);
for c = 1:nCombo
    src_col{c} = R(c).source;  var_col{c} = R(c).variant;
    ci = prctile(macroB(:, c), [2.5 97.5]);
    M(c, :) = [R(c).n_train, R(c).n_test, ...
        100 * mean(R(c).acc), 100 * std(R(c).acc), ...
        mean(R(c).macro), std(R(c).macro), ci(1), ci(2), ...
        100 * mean(R(c).sens(:, 2)), 100 * mean(R(c).ppv(:, 2)), mean(R(c).f1(:, 2)), ...
        100 * mean(R(c).sens(:, 3)), 100 * mean(R(c).ppv(:, 3)), mean(R(c).f1(:, 3)), ...
        mean(R(c).f1(:, 4)), ...
        R(c).te_stats(1), R(c).te_stats(5), R(c).te_stats(4), R(c).te_stats(6)];
end
Tsum = array2table(M, 'VariableNames', {'n_train', 'n_test', 'acc_pct', 'acc_sd_pct', ...
    'macroF1', 'macroF1_sd', 'macroF1_ci_lo', 'macroF1_ci_hi', ...
    'S_sens_pct', 'S_ppv_pct', 'S_F1', 'V_sens_pct', 'V_ppv_pct', 'V_F1', 'F_F1', ...
    'ds2_true_beats', 'ds2_missed_by_detector', 'ds2_false_detections', 'median_peak_offset_samples'});
Tsum = addvars(Tsum, src_col, var_col, 'Before', 1, 'NewVariableNames', {'source', 'variant'});
writetable(Tsum, fullfile(cfg.out_dir, 'integration_summary.csv'));

%% ---------------- paired differences vs 'none' ----------------
rows = {};
metric_names = {'macroF1', 'S_F1', 'V_F1'};
metric_B     = {macroB, sF1B, vF1B};
for s = 1:nS
    base = (s - 1) * nV + find(strcmp(cfg.variant_names, 'none'), 1);
    for v = 1:nV
        if strcmp(cfg.variant_names{v}, 'none'), continue; end
        cc = (s - 1) * nV + v;
        for k = 1:numel(metric_names)
            d  = metric_B{k}(:, cc) - metric_B{k}(:, base);
            ci = prctile(d, [2.5 97.5]);
            if ci(1) > 0 || ci(2) < 0, excl = 'yes'; else, excl = 'no'; end
            rows(end+1, :) = {cfg.sources{s}, cfg.variant_names{v}, metric_names{k}, ...
                mean(d), ci(1), ci(2), excl}; %#ok<SAGROW>
        end
    end
end
Tdiff = cell2table(rows, 'VariableNames', {'source', 'variant', 'metric', ...
    'mean_diff_vs_none', 'ci_lo', 'ci_hi', 'ci_excludes_zero'});
writetable(Tdiff, fullfile(cfg.out_dir, 'integration_vs_none.csv'));

%% ---------------- figure ----------------
fig = figure('Name', 'Integration', 'Position', [100 100 1000 420]);
vals_macro = zeros(nV, nS);  err_macro = zeros(nV, nS);
vals_s     = zeros(nV, nS);
for s = 1:nS
    for v = 1:nV
        cc = (s - 1) * nV + v;
        vals_macro(v, s) = mean(R(cc).macro);
        err_macro(v, s)  = std(R(cc).macro);
        vals_s(v, s)     = mean(R(cc).f1(:, 2));
    end
end
subplot(1, 2, 1);
bar(vals_macro); hold on;
ngroups = nV;  nbars = nS;
for k = 1:nbars
    xk = (1:ngroups) - 0.5 * 0.8 + (2*k - 1) * 0.8 / (2 * nbars);
    errorbar(xk, vals_macro(:, k), err_macro(:, k), 'k.', 'LineWidth', 1);
end
set(gca, 'XTickLabel', cfg.variant_names); ylabel('macro-F1 (N,S,V,F) on DS2');
title('Overall'); legend(cfg.sources, 'Location', 'best'); grid on;
subplot(1, 2, 2);
bar(vals_s);
set(gca, 'XTickLabel', cfg.variant_names); ylabel('F1 of class S on DS2');
title('Supraventricular (S) class'); grid on;
saveas(fig, fullfile(cfg.out_dir, 'integration_figure.png'));

%% ---------------- console summary (also saved to integration_summary.txt) ----------------
diary(summary_file);
fprintf('\n==================== PASTE FROM HERE ====================\n');
fprintf('MATLAB %s\n', version);
fprintf('Model for ALL variants: %s | prior=%s, leaf=%d, trees=%d | seeds=%d | bootstrap=%d patient resamples\n', ...
    model.name, model.prior, model.leaf, model.n_trees, cfg.n_seeds, cfg.n_boot);
fprintf('DS1 records: %d | DS2 records: %d | classes scored in macro-F1: N,S,V,F (Q has only ~7 beats)\n', ...
    numel(ds1_ids), numel(ds2_ids));

for s = 1:nS
    fprintf('\n---- Peak source: %s ----\n', cfg.sources{s});
    fprintf('variant    acc%%   macroF1 [95%% CI]         S sens  S prec  S F1   V F1   missed  false\n');
    for v = 1:nV
        cc = (s - 1) * nV + v;
        ci = prctile(macroB(:, cc), [2.5 97.5]);
        fprintf('%-9s %6.2f   %.3f [%.3f, %.3f]   %5.1f   %5.1f  %5.3f  %5.3f  %6d  %5d\n', ...
            cfg.variant_names{v}, 100 * mean(R(cc).acc), mean(R(cc).macro), ci(1), ci(2), ...
            100 * mean(R(cc).sens(:, 2)), 100 * mean(R(cc).ppv(:, 2)), mean(R(cc).f1(:, 2)), ...
            mean(R(cc).f1(:, 3)), R(cc).te_stats(5), R(cc).te_stats(4));
    end
end

fprintf('\n---- Paired difference vs ''none'' (patient bootstrap; ''yes'' = 95%% CI excludes 0) ----\n');
disp(Tdiff);

fprintf('Detector on DS2 (detected source): true beats / missed / false detections / median peak offset (samples)\n');
for v = 1:nV
    cc = (nS - 1) * nV + v;
    if strcmp(R(cc).source, 'detected')
        fprintf('  %-9s %6d / %5d / %5d / %.1f\n', R(cc).variant, R(cc).te_stats(1), ...
            R(cc).te_stats(5), R(cc).te_stats(4), R(cc).te_stats(6));
    end
end

fprintf('\nSanity: DS1/DS2 overlap = 0 (asserted), NaN in features = 0 (asserted).\n');
fprintf('Reference: your friend''s ground-truth, raw-signal results were baseline 91.48%% acc / macro-F1 0.447 and\n');
fprintf('tuned 88.50%% / 0.460. The groundtruth/none row should be close to the one matching the model above.\n');
fprintf('Total time: %.1f min\n', toc(t_start) / 60);
fprintf('===================== PASTE TO HERE =====================\n');
diary off;
fprintf('\nSaved in %s: integration_summary.csv, integration_vs_none.csv, integration_figure.png, integration_summary.txt\n', cfg.out_dir);

%% ======================= local functions =======================
function ids = ds1_ds2_pick(x)
    ids = x(:);
end

function ds = get_dataset(role, ids, source, vname, vfunc, cfg)
% Load a cached dataset if it was built with identical settings, else build and cache it.
    fn = fullfile(cfg.cache_dir, sprintf('ds_%s_%s_%s.mat', role, source, vname));
    meta = struct('ids', {ids}, 'opts', cfg.ds_opts, 'source', source, 'variant', vname);
    if isfile(fn) && ~cfg.rebuild
        S = load(fn);
        if isequal(S.meta, meta)
            ds = S.ds;
            ds.X = double(ds.X);
            fprintf('  (loaded cached %s dataset: %s)\n', role, fn);
            return;
        end
        fprintf('  (cache settings differ - rebuilding %s dataset)\n', role);
    end
    fprintf('  Building %s dataset (%s, %s) ...\n', role, source, vname);
    ds = build_dataset_variant(ids, vfunc, source, cfg.ds_opts);
    tmp = ds;
    tmp.X = single(ds.X);          % halves the file size
    S2.ds = tmp;
    S2.meta = meta;
    save(fn, '-struct', 'S2', '-v7.3');
end

function m = metrics_from_cm(cm)
% cm: rows = true class, columns = predicted class (order N,S,V,F,Q).
    tp = diag(cm);
    nt = sum(cm, 2);
    np = sum(cm, 1)';
    m.sens = tp ./ nt;
    m.ppv  = tp ./ np;
    m.f1   = 2 * tp ./ (nt + np);
    m.f1(isnan(m.f1)) = 0;
    m.acc  = sum(tp) / sum(cm(:));
    m.macro_f1 = mean(m.f1(1:4));
end

function p = make_prior(Ytr, mode)
    switch mode
        case 'empirical'
            p = 'Empirical';
        case 'uniform'
            p = 'Uniform';
        case 'sqrt'
            [names, ~, ic] = unique(Ytr);
            counts = accumarray(ic, 1);
            probs  = sqrt(counts);
            probs  = probs / sum(probs);
            p = struct('ClassNames', {names}, 'ClassProbs', probs(:)');
        otherwise
            error('Unknown prior mode: %s', mode);
    end
end
