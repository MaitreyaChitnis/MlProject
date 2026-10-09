% PHASE5_TUNING  (A) how many trees? (B) does class weighting help the minority classes?
%
%   A. Tree count : one 300-tree forest, read the out-of-bag (OOB) error at
%                   50/100/200/300 trees to see where it plateaus.
%   B. Weighting  : compare several 'Prior' / MinLeafSize settings using
%                   PATIENT-LEVEL cross-validation inside DS1 (whole patients
%                   are held out, so it is not fooled by same-patient beats).
%   C. Final      : train the winner on all of DS1, test ONCE on DS2.
%
% DS2 is never used to choose any setting.
% Run from the project root. Needs data/processed/features_ds1_ds2.mat.
% Requires the Statistics and Machine Learning Toolbox.

addpath(genpath('src'));

%% ---- settings you may edit ------------------------------------------
tree_counts      = [50 100 200 300];
K_folds          = 3;        % patient-level CV folds (more = slower but steadier)
use_parallel     = false;    % true needs the Parallel Computing Toolbox
n_trees_override = [];       % [] = pick automatically from Section A

configs = struct( ...
    'name',  {'Baseline: empirical prior, leaf 1', ...
              'Uniform prior, leaf 1', ...
              'Uniform prior, leaf 5', ...
              'Sqrt prior, leaf 5'}, ...
    'prior', {'empirical', 'uniform', 'uniform', 'sqrt'}, ...
    'leaf',  {1, 1, 5, 5});
% 'uniform' = every class counts equally; 'sqrt' = halfway between empirical
% and uniform; 'leaf' = MinLeafSize (bigger leaves let the prior matter more).
%% ----------------------------------------------------------------------

par_args = {};
if use_parallel
    par_args = {'Options', statset('UseParallel', true)};
end

mat_file = fullfile('data', 'processed', 'features_ds1_ds2.mat');
if ~isfile(mat_file)
    error('Could not find %s. Run phase3_build.m first.', mat_file);
end
S = load(mat_file);
train = S.train;
test  = S.test;

X_train = train.X;
Y_char  = train.y(:);
Y_train = cellstr(Y_char);
X_test  = test.X;
Y_test  = test.y(:);
classes = 'NSVFQ';
N = size(X_train, 1);

%% ================= A. number of trees (OOB error) =====================
fprintf('=== A. Tree count: training one %d-tree forest ===\n', max(tree_counts));
rng(1);
tic;
m_big = TreeBagger(max(tree_counts), X_train, Y_train, ...
    'OOBPrediction', 'on', par_args{:});
fprintf('Done in %.1f s.\n', toc);

oob = oobError(m_big);     % cumulative OOB error after 1,2,...,300 trees
fprintf('\nOOB error vs number of trees (DS1, beat-level, optimistic):\n');
for t = tree_counts
    fprintf('  %4d trees : OOB error = %.4f  (accuracy %.2f %%)\n', t, oob(t), 100*(1-oob(t)));
end

figure;
plot(oob, 'LineWidth', 1.5); hold on;
plot(tree_counts, oob(tree_counts), 'ro', 'MarkerSize', 8, 'LineWidth', 1.5);
xlabel('Number of trees'); ylabel('OOB classification error (DS1)');
title('OOB error vs number of trees'); grid on;

% smallest tested count whose OOB error is within 0.1 percentage point of the largest
tol = 0.001;
idx = find(oob(tree_counts) <= oob(max(tree_counts)) + tol, 1, 'first');
n_trees_final = tree_counts(idx);
if ~isempty(n_trees_override)
    n_trees_final = n_trees_override;
end
fprintf('\nUsing %d trees for Sections B and C.\n', n_trees_final);
clear m_big;

%% ============ B. class weighting via patient-level CV in DS1 ==========
fprintf('\n=== B. Patient-level %d-fold CV inside DS1 ===\n', K_folds);

n_rec = numel(train.record_ids);
rng(1);
perm = randperm(n_rec);
rec_fold = zeros(n_rec, 1);
rec_fold(perm) = mod(0:n_rec-1, K_folds) + 1;   % each patient gets ONE fold
row_fold = rec_fold(train.row_record);          % every beat inherits its patient's fold

for f = 1:K_folds
    in_f = row_fold == f;
    fprintf('  fold %d: %2d patients, %5d beats  (S=%d, V=%d, F=%d)\n', f, ...
        sum(rec_fold == f), sum(in_f), sum(Y_char(in_f)=='S'), ...
        sum(Y_char(in_f)=='V'), sum(Y_char(in_f)=='F'));
end

nC = numel(configs);
cv_macro = zeros(nC, 1);
cv_sens  = zeros(nC, numel(classes));
cv_ppv   = zeros(nC, numel(classes));

for c = 1:nC
    fprintf('\nConfig %d/%d: %s\n', c, nC, configs(c).name);
    oof_pred = repmat(' ', N, 1);
    for f = 1:K_folds
        tr = row_fold ~= f;
        te = ~tr;
        rng(1);
        mdl = TreeBagger(n_trees_final, X_train(tr,:), Y_train(tr), ...
            'Prior', make_prior(Y_train(tr), configs(c).prior), ...
            'MinLeafSize', configs(c).leaf, par_args{:});
        oof_pred(te) = char(predict(mdl, X_train(te,:)));
        fprintf('  fold %d done\n', f);
    end
    [~, sens, ppv, f1] = score_predictions(Y_char, oof_pred, classes);
    cv_macro(c)  = mean(f1(1:4));     % macro-F1 over N,S,V,F (Q is too tiny to judge)
    cv_sens(c,:) = sens';
    cv_ppv(c,:)  = ppv';
end

fprintf('\n--- Cross-validation summary (pooled over held-out patients) ---\n');
fprintf('%-38s macroF1 | sensS  sensV  sensF | precS  precV  precF\n', 'config');
for c = 1:nC
    fprintf('%-38s %6.3f  | %5.1f  %5.1f  %5.1f | %5.1f  %5.1f  %5.1f\n', configs(c).name, ...
        cv_macro(c), 100*cv_sens(c,2), 100*cv_sens(c,3), 100*cv_sens(c,4), ...
        100*cv_ppv(c,2), 100*cv_ppv(c,3), 100*cv_ppv(c,4));
end
[~, best] = max(cv_macro);
fprintf('\nBest by CV macro-F1: config %d (%s)\n', best, configs(best).name);

%% ================= C. final model, tested once on DS2 =================
fprintf('\n=== C. Training the winner on all of DS1, testing on DS2 ===\n');
rng(1);
tic;
final_model = TreeBagger(n_trees_final, X_train, Y_train, ...
    'Prior', make_prior(Y_train, configs(best).prior), ...
    'MinLeafSize', configs(best).leaf, par_args{:});
fprintf('Trained in %.1f s.\n', toc);

predicted = char(predict(final_model, X_test));
accuracy  = mean(predicted == Y_test);
fprintf('\nDS2 overall accuracy        : %.2f %%\n', 100*accuracy);
fprintf('"Always predict N" baseline : %.2f %%\n', 100*mean(Y_test == 'N'));

[cm, sens, ppv, ~] = score_predictions(Y_test, predicted, classes);
fprintf('\nConfusion matrix (rows = TRUE, columns = PREDICTED), order: %s\n', classes);
disp(array2table(cm, 'VariableNames', cellstr(classes(:))', 'RowNames', cellstr(classes(:))));

base_file = fullfile('data', 'processed', 'baseline_rf.mat');
have_base = isfile(base_file);
if have_base
    B = load(base_file, 'results');
end

fprintf('\nPer-class results on DS2 (new vs. phase4 baseline):\n');
for k = 1:numel(classes)
    line = sprintf('  class %c : %5d beats | sens = %6.2f %% | prec = %6.2f %%', ...
        classes(k), sum(cm(k,:)), 100*sens(k), 100*ppv(k));
    if have_base
        line = sprintf('%s   || baseline: sens = %6.2f %% | prec = %6.2f %%', line, ...
            100*B.results.sensitivity(k), 100*B.results.precision(k));
    end
    fprintf('%s\n', line);
end
fprintf('(NaN = class never predicted / no beats.)\n');

results = struct('accuracy', accuracy, 'confusion', cm, 'classes', classes, ...
    'sensitivity', sens, 'precision', ppv, 'predicted', predicted, 'true', Y_test, ...
    'n_trees', n_trees_final, 'config', configs(best), ...
    'cv_macro_f1', cv_macro, 'cv_sens', cv_sens, 'cv_ppv', cv_ppv, 'oob_error', oob);
model_compact = compact(final_model);
save(fullfile('data', 'processed', 'tuned_rf.mat'), 'results', 'model_compact', '-v7.3');
fprintf('\nSaved to data/processed/tuned_rf.mat\n');

%% ====================== local helper functions ========================
function p = make_prior(Ytr, mode)
% Build the 'Prior' argument from the labels actually present in this training set.
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

function [cm, sens, ppv, f1] = score_predictions(ytrue, ypred, classes)
% Confusion matrix (rows = true, cols = predicted) plus per-class scores.
    order = cellstr(classes(:));
    cm = confusionmat(cellstr(ytrue(:)), cellstr(ypred(:)), 'Order', order);
    tp = diag(cm);
    nt = sum(cm, 2);        % true beats per class
    np = sum(cm, 1)';       % predicted beats per class
    sens = tp ./ nt;
    ppv  = tp ./ np;
    f1   = 2*tp ./ (nt + np);
    f1(isnan(f1)) = 0;
end
