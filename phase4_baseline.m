% PHASE4_BASELINE  First end-to-end result: Random Forest trained on DS1,
% tested on DS2. No tuning - this is just the baseline.
% Run from the project root (Current Folder = folder containing data/ and src/).
% Requires: Statistics and Machine Learning Toolbox, and
%           data/processed/features_ds1_ds2.mat (made by phase3_build.m).

addpath(genpath('src'));
rng(1);   % fixed seed so the result is reproducible

% ---- 1. load the saved DS1 / DS2 matrices ----
mat_file = fullfile('data', 'processed', 'features_ds1_ds2.mat');
if ~isfile(mat_file)
    error('Could not find %s. Run phase3_build.m first.', mat_file);
end
S = load(mat_file);
train = S.train;
test  = S.test;

X_train = train.X;
Y_train = cellstr(train.y(:));   % TreeBagger is happiest with a cell array of labels
X_test  = test.X;
Y_test  = test.y(:);             % char column of true DS2 labels

assert(size(X_train,2) == size(X_test,2), 'Train/test feature counts differ!');
assert(size(X_train,1) == numel(Y_train),  'DS1 rows and labels differ in length!');
assert(size(X_test,1)  == numel(Y_test),   'DS2 rows and labels differ in length!');
fprintf('DS1: %d beats, DS2: %d beats, %d features\n', ...
    size(X_train,1), size(X_test,1), size(X_train,2));

% ---- 2. train ----
n_trees = 100;   % starting point; tune later
fprintf('\nTraining TreeBagger with %d trees (this can take several minutes)...\n', n_trees);
tic;
model = TreeBagger(n_trees, X_train, Y_train, ...
    'OOBPrediction', 'on', ...
    'OOBPredictorImportance', 'on');
fprintf('Training finished in %.1f seconds.\n', toc);

% ---- 3. predict on DS2 ----
pred_cell = predict(model, X_test);
predicted_labels = char(pred_cell);          % cell of 1-char strings -> char column
assert(size(predicted_labels,2) == 1, 'Unexpected label shape from predict().');

% ---- 4. overall accuracy ----
accuracy = mean(predicted_labels == Y_test);
majority_baseline = mean(Y_test == 'N');     % accuracy of "always say N"
fprintf('\n=== RESULT ===\n');
fprintf('DS2 overall accuracy        : %.2f %%\n', 100*accuracy);
fprintf('"Always predict N" baseline : %.2f %%  (a useful model must beat this)\n', 100*majority_baseline);

% ---- 5. per-class breakdown ----
classes = 'NSVFQ';
order = cellstr(classes(:));
cm = confusionmat(cellstr(Y_test), cellstr(predicted_labels), 'Order', order);
% rows = true class, columns = predicted class

fprintf('\nConfusion matrix (rows = TRUE, columns = PREDICTED), order: %s\n', classes);
disp(array2table(cm, 'VariableNames', cellstr(classes(:))', 'RowNames', order));

tp   = diag(cm);
sens = tp ./ sum(cm, 2);          % of the true beats of this class, how many found
ppv  = tp ./ sum(cm, 1)';         % of the beats predicted as this class, how many were right
fprintf('\nPer-class results on DS2:\n');
for k = 1:numel(classes)
    fprintf('  class %c : %5d true beats | sensitivity = %6.2f %% | precision = %6.2f %%\n', ...
        classes(k), sum(cm(k,:)), 100*sens(k), 100*ppv(k));
end
fprintf('(NaN means that class had no beats / no predictions - expected for Q.)\n');

% ---- 6. out-of-bag error on DS1 (for comparison only) ----
oob_err = oobError(model);
fprintf('\nDS1 out-of-bag accuracy: %.2f %%\n', 100*(1 - oob_err(end)));
fprintf('NOTE: OOB is BEAT-level inside DS1 (same patients on both sides), so it is\n');
fprintf('optimistic. The DS2 number above is the honest, patient-level result.\n');

figure;
plot(oob_err, 'LineWidth', 1.5);
xlabel('Number of trees'); ylabel('OOB classification error (DS1)');
title('Out-of-bag error vs number of trees'); grid on;

% ---- 7. feature importance ----
imp = model.OOBPermutedPredictorDeltaError;
[~, order_imp] = sort(imp, 'descend');
fprintf('\nTop 10 most important features:\n');
for j = 1:10
    f = order_imp(j);
    if f <= 3
        names3 = {'RR_prev','RR_next','RR_local_avg'};
        nm = names3{f};
    else
        nm = sprintf('morphology, %+d samples from R-peak', (f-3) - 91);
    end
    fprintf('  %2d. column %3d  %-40s importance %.4f\n', j, f, nm, imp(f));
end

figure;
bar(imp);
xlabel('Feature column (1-3 = RR features, 4-184 = morphology)');
ylabel('Permuted delta error');
title('Feature importance (OOB permutation)'); grid on;

% ---- 8. save results ----
results = struct('accuracy', accuracy, 'majority_baseline', majority_baseline, ...
    'confusion', cm, 'classes', classes, 'sensitivity', sens, 'precision', ppv, ...
    'predicted', predicted_labels, 'true', Y_test, 'n_trees', n_trees);
model_compact = compact(model);   % smaller: drops stored training data
save(fullfile('data', 'processed', 'baseline_rf.mat'), 'results', 'model_compact', '-v7.3');
fprintf('\nSaved results and model to data/processed/baseline_rf.mat\n');
