% PHASE3_BUILD  Build DS1/DS2 feature matrices and save them to disk.
% Run from the project root (Current Folder = folder containing data/ and src/).

addpath(genpath('src'));

[train, test] = build_datasets();

% Final leakage check on what was actually loaded
overlap = intersect(train.record_ids, test.record_ids);
assert(isempty(overlap), 'LEAKAGE: records appear in both train and test!');
fprintf('\nLeakage check passed: no record is in both DS1 and DS2.\n');

out_dir = fullfile('data', 'processed');
if ~isfolder(out_dir)
    mkdir(out_dir);
end
save(fullfile(out_dir, 'features_ds1_ds2.mat'), 'train', 'test', '-v7.3');
fprintf('Saved to %s\n', fullfile(out_dir, 'features_ds1_ds2.mat'));
