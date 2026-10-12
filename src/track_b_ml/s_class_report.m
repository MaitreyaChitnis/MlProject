%S_CLASS_REPORT  Generates detailed S-class and patient-level metrics from results/integration_tuned/
%
%  Run from repo root after rehash:
%      s_class_report

clear; clc;
addpath(genpath('src'));

res_dir = fullfile('results', 'integration_tuned');
if ~isfolder(res_dir)
    error('Results directory %s not found. Run run_integration.m first.', res_dir);
end

summary_out_txt = fullfile(res_dir, 's_class_report_summary.txt');
diary(summary_out_txt);
if isfile(summary_out_txt), delete(summary_out_txt); diary(summary_out_txt); end

fprintf('\n==================== PASTE FROM HERE ====================\n');
fprintf('S-Class & Patient-Level Detailed Report (integration_tuned)\n\n');

% Load record IDs from split JSON
[~, ds2_ids] = load_split();
nRec2 = numel(ds2_ids);

% Find checkpoint files in results/integration_tuned/ or data/processed/variants/
% Let's inspect the variant names and configuration used
variant_names = {'none', 'bandpass', 'wavelet', 'emd', 'highpass', 'lowpass'};
sources = {'groundtruth'};

classes = 'NSVFQ';
nC = numel(classes);

for s = 1:numel(sources)
    src = sources{s};
    for v = 1:numel(variant_names)
        vname = variant_names{v};
        
        % Checkpoint filename convention: result<source>_<variant>_tuned.mat or similar? 
        % Wait, let's check where checkpoints are saved or how run_integration saves them.
        % Actually, run_integration saves percm inside R structure or checkpoint files?
        % Let's look at how run_integration works or check checkpoints in data/processed/variants/ or results/integration_tuned/
        % Wait, the prompt says: "checkpoints are data/processed/variants/result<source>_<variant>_tuned.mat" or let's check cache files.
        % Let's write robust file lookup:
    end
end

% Let's load the dataset or look for checkpoint files
% Actually, let's check what files exist in data/processed/variants/ or results/integration_tuned/
% Let's write code that loads the saved results or re-computes/loads from cache if available, 
% or better yet, load from the saved mat files or variant datasets.
% Wait, let's look at how run_integration stores percm. run_integration doesn't save individual R struct directly unless we look at variants or saved workspaces. 
% Wait! Let's check if there is an integration results file or if we can load the dataset test records to get true patient labels and counts.

fprintf('--- A) Per Variant Metrics (Accuracy, Macro-F1, S-class & V-class) -------\n');
% We can read from integration_summary.csv if it exists
summary_csv = fullfile(res_dir, 'integration_summary.csv');
if isfile(summary_csv)
    Tsum = readtable(summary_csv);
    disp(Tsum(:, {'variant', 'acc_pct', 'macroF1', 'S_sens_pct', 'S_ppv_pct', 'S_F1', 'V_F1'}));
else
    error('Missing integration_summary.csv in %s', res_dir);
end

fprintf('\n--- B) True S-Beat Destination for ''none'' variant -------\n');
% Load the DS2 test dataset for 'none' variant to get confusion matrix breakdown for S true beats
test_ds_file = fullfile('data', 'processed', 'variants', 'ds_test_groundtruth_none.mat');
if ~isfile(test_ds_file)
    error('Missing checkpoint/dataset file: %s', test_ds_file);
end
Dtest = load(test_ds_file);
Yte = Dtest.ds.y(:);
row_record = Dtest.ds.row_record(:);

% We need the predicted labels for 'none' under groundtruth using the tuned model.
% Since we saved percm or can compute predictions, let's load the tuned model or re-predict, 
% OR even simpler: load from the cached datasets and evaluate using the tuned RF model from data/processed/tuned_rf.mat!
tuned_file = fullfile('data', 'processed', 'tuned_rf.mat');
if ~isfile(tuned_file)
    error('Missing tuned model file: %s', tuned_file);
end
T_model = load(tuned_file);

train_ds_file = fullfile('data', 'processed', 'variants', 'ds_train_groundtruth_none.mat');
Dtrain = load(train_ds_file);

rng(1); % seed 1 for reproducibility
mdl = TreeBagger(T_model.results.n_trees, double(Dtrain.ds.X), cellstr(Dtrain.ds.y(:)), ...
    'Prior', make_prior_local(Dtrain.ds.y(:), T_model.results.config.prior), ...
    'MinLeafSize', T_model.results.config.leaf);

pred_none = char(predict(mdl, double(Dtest.ds.X)));

[~, ti] = ismember(Yte, classes);
[~, pj] = ismember(pred_none, classes);

% S class is index 2 ('S')
s_true_idx = find(ti == 2);
s_preds = pj(s_true_idx);

s_counts = accumarray(s_preds, 1, [nC 1]);
total_s = numel(s_true_idx);

fprintf('Total true S beats in DS2 (none variant): %d\n', total_s);
fprintf('Predicted breakdown for true S beats:\n');
for k = 1:nC
    cnt = s_counts(k);
    pct = 100 * cnt / max(total_s, 1);
    fprintf('  True S -> Predicted %c: %3d beats (%5.1f %%)\n', classes(k), cnt, pct);
end

fprintf('\n--- C) Per-DS2-Patient Breakdown for S-Class -------\n');
fprintf('Patient ID | True S | S Found (Pred S) | N-or-other wrongly predicted S\n');
fprintf('-------------------------------------------------------------------\n');

patient_s_true = zeros(nRec2, 1);
patient_s_found = zeros(nRec2, 1);
patient_false_s = zeros(nRec2, 1);

for p = 1:nRec2
    p_mask = (row_record == p);
    
    t_p = ti(p_mask);
    pr_p = pj(p_mask);
    
    true_s_p = sum(t_p == 2);
    found_s_p = sum(t_p == 2 & pr_p == 2);
    false_s_p = sum(t_p ~= 2 & pr_p == 2);
    
    patient_s_true(p) = true_s_p;
    patient_s_found(p) = found_s_p;
    patient_false_s(p) = false_s_p;
    
    fprintf('%10s | %6d | %16d | %28d\n', ds2_ids{p}, true_s_p, found_s_p, false_s_p);
end

[sorted_s_true, sort_idx] = sort(patient_s_true, 'descend');
sorted_ids = ds2_ids(sort_idx);

fprintf('\nPatients ranked by True S count:\n');
for p = 1:nRec2
    fprintf('  %2d. %s: %d true S beats (Found: %d, False S: %d)\n', ...
        p, sorted_ids{p}, patient_s_true(sort_idx(p)), patient_s_found(sort_idx(p)), patient_false_s(sort_idx(p)));
end

total_s_all = sum(patient_s_true);
top1_share = 100 * sorted_s_true(1) / max(total_s_all, 1);
top3_share = 100 * sum(sorted_s_true(1:min(3, numel(sorted_s_true)))) / max(total_s_all, 1);

fprintf('\nConcentration Analysis:\n');
fprintf('  Top 1 patient holds %.1f %% of all true S beats.\n', top1_share);
fprintf('  Top 3 patients hold %.1f %% of all true S beats.\n', top3_share);
fprintf('  Note: Counts are exact for the evaluated seed (seed 1).\n');

fprintf('\n===================== PASTE TO HERE =====================\n');
diary off;
fprintf('Report saved to %s\n', summary_out_txt);

function p = make_prior_local(Ytr, mode)
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