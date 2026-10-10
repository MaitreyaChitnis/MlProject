% PHASE7_CONFUSION  Confusion-matrix analysis of the DS2 results, zooming in on S (SVEB).
%
%   1. confusionmat + confusionchart (counts and row-normalised) for the
%      baseline model (phase 4) and the tuned model (phase 5).
%   2. Zoom on S: where do true S beats go, and what are the beats predicted as S?
%   3. Diagnostics to separate "S is rare" from "S looks like N" from
%      "S sits in only a few patients":
%        a) S beats per record and per-record detection (DS1 counts, DS2 detection)
%        b) timing check: how many beats arrive early (RR_prev / RR_local_avg)
%        c) mean beat shape per class (figure)
%        d) how separable S is from N using the model's vote scores (AUC +
%           sensitivity/precision at lower cut-offs)  -- needs the saved models
%
% This is ANALYSIS ONLY: nothing here changes a model or a setting, and no
% threshold found here should be used for a reported result (it is read off DS2).
%
% Run from the project root. Needs:
%   data/processed/features_ds1_ds2.mat   (phase3_build.m)
%   data/processed/baseline_rf.mat        (phase4_baseline.m)
%   data/processed/tuned_rf.mat           (phase5_tuning.m)   [optional]
% Requires the Statistics and Machine Learning Toolbox.
% Figures and CSVs are saved in the 'results' folder.

addpath(genpath('src'));

%% ---- settings you may edit ------------------------------------------
run_scores_check = true;   % false = skip section 3d (needs loading the saved models)
early_thr        = 0.85;   % RR_prev / RR_local_avg below this counts as "arrived early"
fs               = 360;    % MIT-BIH sampling rate (Hz), only used to label axes in ms
%% ----------------------------------------------------------------------

out_dir = 'results';
if ~isfolder(out_dir), mkdir(out_dir); end

classes = 'NSVFQ';
cats    = cellstr(classes(:));
iS      = find(classes == 'S');

mat_file = fullfile('data', 'processed', 'features_ds1_ds2.mat');
if ~isfile(mat_file)
    error('Could not find %s. Run phase3_build.m first.', mat_file);
end
D = load(mat_file);
train = D.train;
test  = D.test;
ytrue_all = test.y(:);

%% ---- 0. load the saved predictions of each model ----
files = {'baseline_rf.mat', 'Baseline (phase 4)'; ...
         'tuned_rf.mat',    'Tuned (phase 5)'};
M = struct('label', {}, 'file', {}, 'pred', {}, 'cm', {});
for i = 1:size(files, 1)
    fp = fullfile('data', 'processed', files{i,1});
    if ~isfile(fp)
        warning('%s not found - skipping that model.', fp);
        continue;
    end
    R = load(fp, 'results');
    res = R.results;
    assert(isequal(res.true(:), ytrue_all), ...
        '%s: saved true labels do not match DS2 labels. Rerun phase4/phase5 after phase3.', files{i,1});
    cm = confusionmat(cellstr(ytrue_all), cellstr(res.predicted(:)), 'Order', cats);
    assert(isequal(cm, res.confusion), ...
        '%s: recomputed confusion matrix differs from the saved one.', files{i,1});
    M(end+1) = struct('label', files{i,2}, 'file', fp, 'pred', res.predicted(:), 'cm', cm); %#ok<AGROW>
end
if isempty(M)
    error('No saved results found. Run phase4_baseline.m (and phase5_tuning.m) first.');
end
nM = numel(M);

%% ---- 1. confusion matrices and charts ----
t_cat = categorical(cellstr(ytrue_all), cats);
for m = 1:nM
    cm = M(m).cm;
    fprintf('\n===== %s : DS2 confusion matrix (rows = TRUE, columns = PREDICTED) =====\n', M(m).label);
    disp(array2table(cm, 'VariableNames', cellstr(classes(:))', 'RowNames', cats));
    writetable(array2table(cm, 'VariableNames', cellstr(classes(:))', 'RowNames', cats), ...
        fullfile(out_dir, sprintf('confusion_model%d.csv', m)), 'WriteRowNames', true);

    p_cat = categorical(cellstr(M(m).pred), cats);

    fig = figure('Name', ['Confusion chart (counts): ' M(m).label]);
    cc = confusionchart(t_cat, p_cat, ...
        'RowSummary', 'row-normalized', 'ColumnSummary', 'column-normalized');
    cc.Title = ['DS2 confusion matrix (counts) - ' M(m).label];
    saveas(fig, fullfile(out_dir, sprintf('confusion_counts_model%d.png', m)));

    fig = figure('Name', ['Confusion chart (row-normalised): ' M(m).label]);
    cc = confusionchart(t_cat, p_cat);
    cc.Normalization = 'row-normalized';
    cc.Title = ['DS2 confusion matrix (% of each true class) - ' M(m).label];
    saveas(fig, fullfile(out_dir, sprintf('confusion_rownorm_model%d.png', m)));
end

%% ---- 2. zoom in on S ----
rowS_pct = zeros(nM, numel(classes));
colS_cnt = zeros(nM, numel(classes));
for m = 1:nM
    cm = M(m).cm;
    rowS_pct(m, :) = 100 * cm(iS, :) / sum(cm(iS, :));
    colS_cnt(m, :) = cm(:, iS)';

    fprintf('\n----- %s : the S row and S column -----\n', M(m).label);
    fprintf('Where do the %d true S beats go?\n', sum(cm(iS, :)));
    for k = 1:numel(classes)
        fprintf('   true S -> predicted %c : %5d  (%5.1f %% of true S beats)\n', ...
            classes(k), cm(iS, k), rowS_pct(m, k));
    end
    fprintf('What are the %d beats the model called S, really?\n', sum(cm(:, iS)));
    for k = 1:numel(classes)
        fprintf('   truly %c, predicted S : %5d  (%5.1f %% of beats predicted S)\n', ...
            classes(k), cm(k, iS), 100 * cm(k, iS) / max(sum(cm(:, iS)), 1));
    end
end
fprintf('\nClass balance in DS2: %d N beats per 1 S beat.  S = %.2f %% of DS1, %.2f %% of DS2.\n', ...
    round(sum(test.y(:) == 'N') / sum(test.y(:) == 'S')), ...
    100 * mean(train.y(:) == 'S'), 100 * mean(test.y(:) == 'S'));

fig = figure('Name', 'S zoom');
subplot(1, 2, 1);
bar(rowS_pct');
set(gca, 'XTickLabel', cellstr(classes(:)));
xlabel('Predicted class'); ylabel('% of true S beats');
title('Where do true S beats go?');
legend({M.label}, 'Location', 'northeast', 'Interpreter', 'none'); grid on;
subplot(1, 2, 2);
bar(colS_cnt');
set(gca, 'XTickLabel', cellstr(classes(:)));
xlabel('TRUE class of the beat'); ylabel('Number of beats predicted S');
title('What is behind the "S" predictions?');
grid on;
saveas(fig, fullfile(out_dir, 'S_zoom.png'));

%% ---- 3a. S beats per record (is S concentrated in a few patients?) ----
fprintf('\n===== S beats per patient =====\n');
print_s_counts(train, 'DS1 (training)');
for m = 1:nM
    print_s_by_record(test, ytrue_all, M(m).pred, sprintf('DS2, %s', M(m).label));
end

%% ---- 3b. timing check ----
fprintf('\n===== Timing check: RR_prev / RR_local_avg (below %.2f = "arrived early") =====\n', early_thr);
fprintf('(RR_local_avg includes RR_prev, so the ratio is squeezed toward 1; %.2f is approximate.)\n', early_thr);
fprintf('class |  DS1 median  %% early |  DS2 median  %% early\n');
for c = 'NSVF'
    r1 = train.X(train.y(:) == c, 1) ./ train.X(train.y(:) == c, 3);
    r2 = test.X(test.y(:)  == c, 1) ./ test.X(test.y(:)  == c, 3);
    fprintf('  %c   |  %9.3f  %7.1f   |  %9.3f  %7.1f\n', c, median(r1), 100*mean(r1 < early_thr), ...
        median(r2), 100*mean(r2 < early_thr));
end

%% ---- 3c. mean beat shape per class (DS1) ----
t_ms = (-90:90) / fs * 1000;
fig = figure('Name', 'Mean beat per class');
hold on;
for c = 'NSVF'
    plot(t_ms, mean(train.X(train.y(:) == c, 4:end), 1), 'LineWidth', 1.5);
end
legend({'N', 'S', 'V', 'F'}); grid on;
xlabel('Time relative to R-peak (ms)'); ylabel('Mean beat amplitude (mV)');
title('Mean beat shape per class (DS1, MLII lead)');
saveas(fig, fullfile(out_dir, 'mean_beats_per_class.png'));

%% ---- 3d. how separable is S from N? (vote scores of the saved models) ----
if run_scores_check
    fprintf('\n===== Is S separable from N? (model vote scores on DS2) =====\n');
    isS = double(ytrue_all == 'S');
    isSN = (ytrue_all == 'S') | (ytrue_all == 'N');
    for m = 1:nM
        W = load(M(m).file, 'model_compact');
        mdl = W.model_compact;
        [~, sc] = predict(mdl, test.X);
        cS = find(strcmp(mdl.ClassNames, 'S'));
        sS = sc(:, cS);

        [~, ~, ~, auc_rest] = perfcurve(isS, sS, 1);
        [~, ~, ~, auc_N]    = perfcurve(isS(isSN), sS(isSN), 1);
        fprintf('\n%s\n', M(m).label);
        fprintf('  AUC, S vs everything else : %.3f\n', auc_rest);
        fprintf('  AUC, S vs N only          : %.3f   (0.5 = no better than chance, 1.0 = perfectly separable)\n', auc_N);
        fprintf('  If we called a beat S whenever its S-vote fraction >= cut-off (diagnostic only):\n');
        for thr = [0.50 0.30 0.20 0.10 0.05]
            pS = sS >= thr;
            tp = sum(pS & isS == 1);
            fp = sum(pS & isS == 0);
            fprintf('    cut-off %.2f : S sensitivity %5.1f %% | precision %5.1f %% | %5d false alarms\n', ...
                thr, 100 * tp / sum(isS), 100 * tp / max(tp + fp, 1), fp);
        end
        clear mdl W sc;
    end
    fprintf('\nReminder: these cut-offs are read off DS2, so they show what is POSSIBLE,\n');
    fprintf('not a result you may report. Choosing a cut-off must be done inside DS1.\n');
end

fprintf('\nFigures and CSVs are in "%s".\n', out_dir);

%% ====================== local helper functions ========================
function print_s_counts(ds, label)
    nrec = numel(ds.record_ids);
    nS = accumarray(ds.row_record, double(ds.y(:) == 'S'), [nrec 1]);
    [sorted, ord] = sort(nS, 'descend');
    total = sum(nS);
    fprintf('\n%s: %d S beats in total, spread over %d of %d records.\n', ...
        label, total, nnz(nS), nrec);
    fprintf('  Top records by S count: ');
    for j = 1:min(5, nnz(nS))
        fprintf('%s (%d)  ', ds.record_ids{ord(j)}, sorted(j));
    end
    fprintf('\n  Top record = %.0f %% of all S beats, top 3 = %.0f %%.\n', ...
        100 * sorted(1) / total, 100 * sum(sorted(1:min(3, end))) / total);
end

function print_s_by_record(ds, ytrue, ypred, label)
    nrec = numel(ds.record_ids);
    rr   = ds.row_record;
    nS   = accumarray(rr, double(ytrue == 'S'), [nrec 1]);
    detS = accumarray(rr, double(ytrue == 'S' & ypred == 'S'), [nrec 1]);
    fpS  = accumarray(rr, double(ytrue == 'N' & ypred == 'S'), [nrec 1]);
    [sorted, ord] = sort(nS, 'descend');
    total = sum(nS);

    fprintf('\n%s: %d S beats, spread over %d of %d records.\n', label, total, nnz(nS), nrec);
    fprintf('  record | true S | found | S sensitivity | N wrongly called S\n');
    for j = 1:min(8, nnz(nS))
        k = ord(j);
        fprintf('  %-6s | %6d | %5d | %9.1f %%   | %5d\n', ...
            ds.record_ids{k}, nS(k), detS(k), 100 * detS(k) / nS(k), fpS(k));
    end
    top = ord(1);
    fprintf('  Top record holds %.0f %% of all S beats.\n', 100 * sorted(1) / total);
    if total - nS(top) > 0
        fprintf('  Pooled S sensitivity = %.1f %%;  excluding the top record = %.1f %%.\n', ...
            100 * sum(detS) / total, 100 * (sum(detS) - detS(top)) / (total - nS(top)));
    end
end
