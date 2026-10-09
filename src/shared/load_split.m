function [ds1_ids, ds2_ids, excluded_ids] = load_split(json_path)
% LOAD_SPLIT  Read the DS1/DS2 record lists from the split JSON file.
%
%   [ds1_ids, ds2_ids] = load_split()
%   [ds1_ids, ds2_ids, excluded_ids] = load_split('data/splits/ds1_ds2_split.json')
%
% Returns cell arrays (column) of char record IDs, e.g. {'101'; '106'; ...}.
% Record numbers are NEVER typed anywhere in the code - they come only from
% the JSON file. This function also runs leakage/integrity checks and
% errors out loudly if anything is wrong.

    if nargin < 1 || isempty(json_path)
        json_path = fullfile('data', 'splits', 'ds1_ds2_split.json');
    end
    if ~isfile(json_path)
        error('load_split:FileNotFound', ...
            ['Could not find "%s".\nRun MATLAB from the project root ' ...
             '(the folder that contains data/ and src/).'], json_path);
    end

    s = jsondecode(fileread(json_path));

    ds1_ids      = to_cellstr(s.ds1_training);
    ds2_ids      = to_cellstr(s.ds2_testing);
    excluded_ids = to_cellstr(s.excluded_paced_patients);

    % ---- integrity checks ----
    % 1. counts must match what the JSON itself says it expects
    exp = s.expected_counts;
    if numel(ds1_ids) ~= exp.ds1_records
        error('load_split:BadCount', 'ds1_training has %d records, JSON expects %d.', ...
            numel(ds1_ids), exp.ds1_records);
    end
    if numel(ds2_ids) ~= exp.ds2_records
        error('load_split:BadCount', 'ds2_testing has %d records, JSON expects %d.', ...
            numel(ds2_ids), exp.ds2_records);
    end
    if numel(excluded_ids) ~= exp.excluded_records
        error('load_split:BadCount', 'excluded list has %d records, JSON expects %d.', ...
            numel(excluded_ids), exp.excluded_records);
    end

    % 2. no duplicates inside a list
    if numel(unique(ds1_ids)) ~= numel(ds1_ids) || numel(unique(ds2_ids)) ~= numel(ds2_ids)
        error('load_split:Duplicates', 'A record ID appears twice inside one list.');
    end

    % 3. PATIENT-LEVEL LEAKAGE CHECK: nothing in both train and test
    overlap = intersect(ds1_ids, ds2_ids);
    if ~isempty(overlap)
        error('load_split:Leakage', 'Records in BOTH DS1 and DS2: %s', strjoin(overlap', ', '));
    end

    % 4. excluded (paced) patients must not be in either list
    bad = [intersect(excluded_ids, ds1_ids); intersect(excluded_ids, ds2_ids)];
    if ~isempty(bad)
        error('load_split:ExcludedUsed', 'Excluded records found in a split: %s', strjoin(bad', ', '));
    end
end

function c = to_cellstr(x)
% jsondecode gives a cell column for a list of strings; normalise edge cases.
    if ischar(x)
        c = {x};
    elseif isstring(x)
        c = cellstr(x);
    else
        c = x;
    end
    c = c(:);
end
