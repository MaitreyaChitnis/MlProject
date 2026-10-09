% PHASE6_IMPORTANCE  Which features does the Random Forest actually rely on?
%
%   1. Trains the baseline model and the phase-5 tuned model on DS1 with
%      OOB permutation importance switched on.
%   2. Prints the top features, draws a sorted bar chart, and plots importance
%      against time relative to the R-peak (with mean N and V beats overlaid).
%   3. Cross-checks the OOB ranking with a GROUPED permutation test on DS2
%      (shuffle a whole group of features, measure how much performance drops).
%      This does NOT change any model or setting - it is analysis only.
%
% Run from the project root. Needs data/processed/features_ds1_ds2.mat
% (and data/processed/tuned_rf.mat from phase5_tuning.m for the second model).
% Requires the Statistics and Machine Learning Toolbox.
% Figures and CSV tables are saved in the 'results' folder.

addpath(genpath('src'));

%% ---- settings you may edit ------------------------------------------
n_repeats     = 3;      % shuffles per group in the DS2 check (more = steadier, slower)
top_n         = 20;     % bars in the sorted chart
run_ds2_check = true;   % false = skip Section 3 (much faster)
fs            = 360;    % MIT-BIH sampling rate in Hz (only used to label axes in ms)
half_window   = 90;     % must match extract_features default
%% ----------------------------------------------------------------------

out_dir = 'results';
if ~isfolder(out_dir), mkdir(out_dir); end

mat_file = fullfile('data', 'processed', 'features_ds1_ds2.mat');
if ~isfile(mat_file)
    error('Could not find %s. Run phase3_build.m first.', mat_file);
end
S = load(mat_file);
train = S.train;
test  = S.test;

X_train = train.X;
Y_train = cellstr(train.y(:));
X_test  = test.X;
Y_test  = test.y(:);
n_feat  = size(X_train, 2);
assert(half_window == 90, 'Groups below assume half_window = 90.');
assert(n_feat == 3 + 2*half_window + 1, 'Feature count does not match half_window.');

%% ---- which models to analyse ----
models = struct('name', {}, 'prior', {}, 'leaf', {}, 'n_trees', {});
models(1) = struct('name', 'Baseline (empirical prior, leaf 1)', ...
                   'prior', 'empirical', 'leaf', 1, 'n_trees', 100);
tuned_file = fullfile('data', 'processed', 'tuned_rf.mat');
if isfile(tuned_file)
    T = load(tuned_file, 'results');
    cfg = T.results.config;
    models(2) = struct('name', ['Tuned: ' cfg.name], 'prior', cfg.prior, ...
                       'leaf', cfg.leaf, 'n_trees', T.results.n_trees);
else
    warning('tuned_rf.mat not found - analysing the baseline model only.');
end

% ---- feature groups for the DS2 check (column = 3 + offset + half_window + 1) ----
col = @(o) 3 + o + half_window + 1;
groups = struct('name', {}, 'cols', {});
groups(end+1) = struct('name', 'RR_prev',            'cols', 1);
groups(end+1) = struct('name', 'RR_next',            'cols', 2);
groups(end+1) = struct('name', 'RR_local_avg',       'cols', 3);
groups(end+1) = struct('name', 'All 3 RR features',  'cols', 1:3);
blocks  = [-90 -46; -45 -16; -15 15; 16 45; 46 90];
blabels = {'P wave / PR segment', 'QRS onset', 'QRS core (R-peak)', ...
           'QRS end / J-point', 'ST segment / T onset'};
for b = 1:size(blocks, 1)
    groups(end+1) = struct( ...
        'name', sprintf('Morph %+d..%+d (%s)', blocks(b,1), blocks(b,2), blabels{b}), ...
        'cols', col(blocks(b,1)) : col(blocks(b,2)));
end
groups(end+1) = struct('name', 'All morphology (181 samples)', 'cols', 4:n_feat);

% mean N and V beat shapes (for the overlay figure)
off    = -half_window:half_window;
t_ms   = off / fs * 1000;
morph  = X_train(:, 4:end);
mean_N = mean(morph(train.y(:) == 'N', :), 1);
mean_V = mean(morph(train.y(:) == 'V', :), 1);

nM   = numel(models);
imps = cell(nM, 1);
R    = struct('name', {}, 'importance', {}, 'top_idx', {}, 'ds2_groups', {});

for m = 1:nM
    fprintf('\n=================================================\n');
    fprintf('Model %d/%d: %s  (%d trees)\n', m, nM, models(m).name, models(m).n_trees);
    fprintf('=================================================\n');

    %% ---- 1. train with importance on ----
    rng(1);
    tic;
    mdl = TreeBagger(models(m).n_trees, X_train, Y_train, ...
        'OOBPrediction', 'on', 'OOBPredictorImportance', 'on', ...
        'Prior', make_prior(Y_train, models(m).prior), ...
        'MinLeafSize', models(m).leaf);
    fprintf('Trained in %.1f s.\n', toc);

    imp = mdl.OOBPermutedPredictorDeltaError(:);   % one score per feature column
    imps{m} = imp;
    [~, ord] = sort(imp, 'descend');

    %% ---- 2. report ----
    fprintf('\nTop 15 features (OOB permutation importance):\n');
    for j = 1:15
        f = ord(j);
        fprintf('  %2d. column %3d  %-40s importance %.4f\n', j, f, ...
            feat_name(f, half_window, fs), imp(f));
    end
    n_after  = sum(ord(1:10) > 3 & (ord(1:10) - 3 - (half_window+1)) > 0);
    n_before = sum(ord(1:10) > 3 & (ord(1:10) - 3 - (half_window+1)) < 0);
    fprintf('\nOf the top 10: %d RR features, %d morphology samples AFTER the R-peak, %d BEFORE it.\n', ...
        sum(ord(1:10) <= 3), n_after, n_before);
    fprintf('Mean importance per column: RR features = %.3f, morphology samples = %.3f\n', ...
        mean(imp(1:3)), mean(imp(4:end)));
    fprintf('(Scores are normalised by their spread across trees: compare them to each\n');
    fprintf(' other, do not read them as "percent error increase".)\n');

    % sorted bar chart
    labels = arrayfun(@(f) short_name(f, half_window), ord(1:top_n), 'UniformOutput', false);
    fig1 = figure('Name', sprintf('Top features - model %d', m));
    bar(imp(ord(1:top_n)));
    xticks(1:top_n); xticklabels(labels); xtickangle(60);
    ylabel('OOB permutation importance');
    title(sprintf('Top %d features: %s', top_n, models(m).name), 'Interpreter', 'none');
    xlabel('m+k = morphology sample k samples after the R-peak (m-k = before)');
    grid on;
    saveas(fig1, fullfile(out_dir, sprintf('importance_top%d_model%d.png', top_n, m)));

    % importance along the beat, with mean N and V beats overlaid
    fig2 = figure('Name', sprintf('Importance vs time - model %d', m));
    yyaxis left;
    plot(t_ms, mean_N, 'LineWidth', 1.5); hold on;
    plot(t_ms, mean_V, 'LineWidth', 1.5);
    ylabel('Mean beat amplitude (mV)');
    yyaxis right;
    plot(t_ms, imp(4:end), 'LineWidth', 1.5);
    ylabel('Permutation importance (per sample)');
    xlabel('Time relative to R-peak (ms)');
    legend({'Mean N beat', 'Mean V beat', 'Importance'}, 'Location', 'northwest');
    title(sprintf('Where the model looks: %s', models(m).name), 'Interpreter', 'none');
    grid on;
    saveas(fig2, fullfile(out_dir, sprintf('importance_vs_time_model%d.png', m)));

    % CSV of the top features
    names_top = arrayfun(@(f) feat_name(f, half_window, fs), ord(1:top_n), 'UniformOutput', false);
    tbl_top = table((1:top_n)', ord(1:top_n), names_top, imp(ord(1:top_n)), ...
        'VariableNames', {'Rank', 'Column', 'Feature', 'Importance'});
    writetable(tbl_top, fullfile(out_dir, sprintf('importance_top%d_model%d.csv', top_n, m)));

    %% ---- 3. grouped permutation check on DS2 (analysis only) ----
    tbl_groups = [];
    if run_ds2_check
        fprintf('\n--- Grouped permutation check on DS2 (%d shuffles per group) ---\n', n_repeats);
        tbl_groups = ds2_group_check(mdl, X_test, Y_test, groups, n_repeats);
        disp(tbl_groups);
        fprintf('Bigger drop = the model depends more on that group on unseen patients.\n');
        writetable(tbl_groups, fullfile(out_dir, sprintf('ds2_group_importance_model%d.csv', m)));
    end

    R(m).name = models(m).name;
    R(m).importance = imp;
    R(m).top_idx = ord(1:top_n);
    R(m).ds2_groups = tbl_groups;
    clear mdl;
end

%% ---- compare the two models' rankings ----
if nM >= 2
    rho = corr(imps{1}, imps{2}, 'Type', 'Spearman');
    [~, o1] = sort(imps{1}, 'descend');
    [~, o2] = sort(imps{2}, 'descend');
    fprintf('\nSpearman rank correlation between the two models'' importances: %.3f\n', rho);
    fprintf('Top-10 overlap between the two models: %d of 10 features\n', ...
        numel(intersect(o1(1:10), o2(1:10))));
end

save(fullfile('data', 'processed', 'importance_results.mat'), 'R', 'groups');
fprintf('\nFigures and CSVs are in "%s"; values saved to data/processed/importance_results.mat\n', out_dir);

%% ====================== local helper functions ========================
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

function s = feat_name(f, half_window, fs)
    if f <= 3
        names3 = {'RR_prev', 'RR_next', 'RR_local_avg'};
        s = names3{f};
    else
        o = (f - 3) - (half_window + 1);
        s = sprintf('morphology %+d samples (%+.0f ms)', o, o / fs * 1000);
    end
end

function s = short_name(f, half_window)
    if f <= 3
        names3 = {'RR_prev', 'RR_next', 'RR_local_avg'};
        s = names3{f};
    else
        s = sprintf('m%+d', (f - 3) - (half_window + 1));
    end
end

function tbl = ds2_group_check(mdl, X_test, Y_test, groups, n_repeats)
% Shuffle each feature group (whole rows together, so within-beat structure is
% kept) and report how much accuracy and macro-F1 (N,S,V,F) drop on DS2.
    classes = 'NSVFQ';
    base_pred = char(predict(mdl, X_test));
    [~, ~, ~, f1b] = score_predictions(Y_test, base_pred, classes);
    base_acc = mean(base_pred == Y_test);
    base_mf1 = mean(f1b(1:4));
    fprintf('Unshuffled DS2: accuracy %.2f %%, macro-F1 %.3f\n', 100*base_acc, base_mf1);

    n  = size(X_test, 1);
    ng = numel(groups);
    d_acc = zeros(ng, 1);
    d_mf1 = zeros(ng, 1);
    for g = 1:ng
        a = zeros(n_repeats, 1);
        f = zeros(n_repeats, 1);
        for r = 1:n_repeats
            rng(r);
            Xp = X_test;
            Xp(:, groups(g).cols) = X_test(randperm(n), groups(g).cols);
            pred = char(predict(mdl, Xp));
            [~, ~, ~, f1p] = score_predictions(Y_test, pred, classes);
            a(r) = base_acc - mean(pred == Y_test);
            f(r) = base_mf1 - mean(f1p(1:4));
        end
        d_acc(g) = mean(a);
        d_mf1(g) = mean(f);
        fprintf('  done: %s\n', groups(g).name);
    end
    tbl = table({groups.name}', 100*d_acc, d_mf1, ...
        'VariableNames', {'Group', 'AccuracyDrop_pct', 'MacroF1Drop'});
end

function [cm, sens, ppv, f1] = score_predictions(ytrue, ypred, classes)
    order = cellstr(classes(:));
    cm = confusionmat(cellstr(ytrue(:)), cellstr(ypred(:)), 'Order', order);
    tp = diag(cm);
    nt = sum(cm, 2);
    np = sum(cm, 1)';
    sens = tp ./ nt;
    ppv  = tp ./ np;
    f1   = 2*tp ./ (nt + np);
    f1(isnan(f1)) = 0;
end
