%CHECK_VS_FRIEND  Why does run_integration's groundtruth/none row (about 92.5 % accuracy)
%  differ from your friend's phase4 baseline (91.48 %)?  Two candidate causes are
%  tested separately with a 2 x 2 design:
%     DATA   : his saved features_ds1_ds2.mat   vs   the cached run_integration data
%              (which is stored in single precision)
%     CALL   : his TreeBagger call (OOBPrediction + OOBPredictorImportance on)
%              vs   the run_integration call (default options)
%  Everything uses rng(1) immediately before training, 100 trees.
%
%  Run from the repo root:   check_vs_friend
%  NEEDS:  data\processed\features_ds1_ds2.mat   (made by phase3_build.m)
%          data\processed\variants\ds_*_groundtruth_none.mat  (made by run_integration)
%  RUNTIME: roughly 10-20 minutes (his call also computes permutation importance).
%  Paste the block between PASTE FROM HERE and PASTE TO HERE.

clear; clc;
addpath(genpath('src'));
t_start = tic;
classes = 'NSVFQ';
nC = numel(classes);

fa    = fullfile('data', 'processed', 'features_ds1_ds2.mat');
fb_tr = fullfile('data', 'processed', 'variants', 'ds_train_groundtruth_none.mat');
fb_te = fullfile('data', 'processed', 'variants', 'ds_test_groundtruth_none.mat');
for f = {fa, fb_tr, fb_te}
    if ~isfile(f{1})
        error('Missing %s\nRun phase3_build.m (for features_ds1_ds2.mat) or run_integration.m first.', f{1});
    end
end

A = load(fa);
Btr = load(fb_tr, 'ds');
Bte = load(fb_te, 'ds');
XaTr = A.train.X;           yaTr = A.train.y(:);
XaTe = A.test.X;            yaTe = A.test.y(:);
XbTr = double(Btr.ds.X);    ybTr = Btr.ds.y(:);
XbTe = double(Bte.ds.X);    ybTe = Bte.ds.y(:);

fprintf('==================== PASTE FROM HERE ====================\n');
fprintf('MATLAB %s\n\n', version);
fprintf('---- 1. Are the two datasets the same? ----\n');
report('DS1 (train)', XaTr, yaTr, XbTr, ybTr);
report('DS2 (test) ', XaTe, yaTe, XbTe, ybTe);

fprintf('\n---- 2. Training 2 x 2 (rng(1), 100 trees, tested on DS2) ----\n');
fprintf('data           call                 acc %%   macro-F1 (N,S,V,F)   S sens %%\n');
datas = {'friend file', 'cached (single)'};
Xtrs  = {XaTr, XbTr};  Ytrs = {yaTr, ybTr};
Xtes  = {XaTe, XbTe};  Ytes = {yaTe, ybTe};
calls = {'friend (OOB on)', 'default options'};
for d = 1:2
    for k = 1:2
        rng(1);
        if k == 1
            mdl = TreeBagger(100, Xtrs{d}, cellstr(Ytrs{d}), ...
                'OOBPrediction', 'on', 'OOBPredictorImportance', 'on');
        else
            mdl = TreeBagger(100, Xtrs{d}, cellstr(Ytrs{d}), 'Prior', 'Empirical', 'MinLeafSize', 1);
        end
        pred = char(predict(mdl, Xtes{d}));
        clear mdl;
        [~, ti] = ismember(Ytes{d}, classes);
        [~, pj] = ismember(pred, classes);
        cm = accumarray([ti pj], 1, [nC nC]);
        tp = diag(cm);  nt = sum(cm, 2);  np = sum(cm, 1)';
        f1 = 2 * tp ./ (nt + np);  f1(isnan(f1)) = 0;
        fprintf('%-14s %-18s %7.2f   %.3f               %5.1f\n', datas{d}, calls{k}, ...
            100 * sum(tp) / sum(cm(:)), mean(f1(1:4)), 100 * tp(2) / nt(2));
    end
end
fprintf('\nReading it: if the two rows of the SAME data agree but the two datasets differ, the data are\n');
fprintf('the cause. If rows with the SAME call agree but the two calls differ, the options are the cause.\n');
fprintf('Total time: %.1f min\n', toc(t_start) / 60);
fprintf('===================== PASTE TO HERE =====================\n');

function report(name, Xa, ya, Xb, yb)
    fprintf('%s: friend %d x %d | cached %d x %d\n', name, size(Xa, 1), size(Xa, 2), size(Xb, 1), size(Xb, 2));
    if ~isequal(size(Xa), size(Xb))
        fprintf('   SIZES DIFFER - the datasets are not the same beats/features.\n');
        return;
    end
    d = abs(Xa - Xb);
    rel = d ./ max(abs(Xa), 1e-12);
    fprintf('   labels identical: %d | max abs diff %.3g | max rel diff %.3g | entries differing by >1e-6: %d\n', ...
        isequal(ya, yb), max(d(:)), max(rel(:)), nnz(d > 1e-6));
end
