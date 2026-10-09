function [train, test] = build_datasets(data_dir)
% BUILD_DATASETS  Build the DS1 (train) and DS2 (test) feature matrices.
%
%   [train, test] = build_datasets()
%   [train, test] = build_datasets('data/raw')
%
% Record IDs come ONLY from data/splits/ds1_ds2_split.json via load_split.m.
%
% Each output is a struct:
%   .X          [nBeats x 184] features (RR_prev, RR_next, RR_local_avg, morphology)
%   .y          [nBeats x 1] char AAMI labels
%   .record_ids cell array of the record IDs used (in order)
%   .row_record [nBeats x 1] index into .record_ids telling which patient
%               each row came from (useful for patient-level analysis)

    if nargin < 1 || isempty(data_dir)
        data_dir = fullfile('data', 'raw');
    end

    [ds1_ids, ds2_ids] = load_split();

    fprintf('=== Building DS1 (training), %d records ===\n', numel(ds1_ids));
    train = build_one_set(ds1_ids, data_dir);
    print_summary('DS1', train);

    fprintf('\n=== Building DS2 (testing), %d records ===\n', numel(ds2_ids));
    test = build_one_set(ds2_ids, data_dir);
    print_summary('DS2', test);
end

% ---------------------------------------------------------------------
function ds = build_one_set(ids, data_dir)
    n = numel(ids);
    Xc = cell(n, 1);
    yc = cell(n, 1);
    rc = cell(n, 1);

    for k = 1:n
        id = ids{k};
        try
            record = load_record(id, data_dir);
            lead   = pick_lead(data_dir, id);
            [X, y] = extract_features(record, lead);
        catch ME
            % fail loudly: silently skipping a record would corrupt the split
            error('build_datasets:RecordFailed', ...
                'Record %s failed: %s', id, ME.message);
        end
        Xc{k} = X;
        yc{k} = y;
        rc{k} = k * ones(size(X, 1), 1);
        fprintf('  record %s: lead %d, %d beats kept\n', id, lead, size(X, 1));
    end

    ds.X          = vertcat(Xc{:});
    ds.y          = vertcat(yc{:});
    ds.row_record = vertcat(rc{:});
    ds.record_ids = ids;
end

% ---------------------------------------------------------------------
function lead = pick_lead(data_dir, id)
% Choose the MLII (Lead II) column using the record's own header, so no
% record numbers need to be typed by hand. Falls back to column 1 with a warning.
    info = parse_mitbih_header(fullfile(data_dir, [id '.hea']));
    lead = 0;
    for k = 1:info.nSignals
        if strcmpi(strtrim(info.signals(k).description), 'MLII')
            lead = k;
            break;
        end
    end
    if lead == 0
        lead = 1;
        warning('build_datasets:NoMLII', ...
            'Record %s has no MLII lead in its header; using column 1.', id);
    end
end

% ---------------------------------------------------------------------
function print_summary(name, ds)
    fprintf('%s total: %d beats x %d features\n', name, size(ds.X, 1), size(ds.X, 2));
    for c = 'NSVFQ'
        fprintf('  class %c: %d\n', c, sum(ds.y == c));
    end
    if any(isnan(ds.X(:)))
        warning('build_datasets:NaN', '%s contains NaN values!', name);
    end
end
