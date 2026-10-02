function record = load_record(record_id, data_dir)
% LOAD_RECORD  Load one MIT-BIH record (signal + annotations) into a struct.
%
% This is the SHARED loader both Track A and Track B must use, so that
% everyone reads the exact same signal, in the exact same way, every time.
% Do not write a second/competing loader elsewhere in the codebase.
%
%   record = load_record('100')
%   record = load_record('100', 'data/raw')
%
% INPUTS
%   record_id : string or char, e.g. '100' (must match a <id>.dat/.hea/.atr trio)
%   data_dir  : (optional) folder containing the raw files.
%               Defaults to 'data/raw' relative to the current MATLAB path,
%               which assumes you're running from the project root.
%
% OUTPUT (struct 'record' with fields)
%   record.id          : the record id you asked for, as a string
%   record.signal      : Nx1 (or NxM for multi-lead) numeric array, the ECG signal
%   record.fs          : sampling frequency in Hz (360 for MIT-BIH)
%   record.ann_samples : column vector of sample indices where each annotated beat occurs
%   record.ann_symbols : cell array of annotation symbols (e.g. 'N','V','A',...),
%                        same length and order as ann_samples
%
% REQUIRES: WFDB Toolbox for MATLAB (rdsamp, rdann) must be installed and on path.
% Install/download instructions: https://physionet.org/content/wfdb-matlab/

    if nargin < 2 || isempty(data_dir)
        data_dir = fullfile('data', 'raw');
    end

    record_id = char(record_id); % normalize to char in case a string was passed

    % Full path prefix WFDB functions expect (no file extension)
    record_path = fullfile(data_dir, record_id);

    hea_file = [record_path '.hea'];
    dat_file = [record_path '.dat'];
    atr_file = [record_path '.atr'];

    if ~isfile(hea_file) || ~isfile(dat_file) || ~isfile(atr_file)
        error('load_record:MissingFiles', ...
            ['Could not find all three files for record "%s" in "%s".\n' ...
             'Expected: %s.hea, %s.dat, %s.atr'], ...
             record_id, data_dir, record_id, record_id, record_id);
    end

    % --- Read the signal ---
    % rdsamp returns: tm (time vector), signal (samples x leads), Fs, siginfo
    [~, signal, Fs] = rdsamp(record_path);

    % --- Read the annotations (ground-truth beat labels/locations) ---
    % rdann returns sample indices (ann) and symbol codes (type) for each annotation
    [ann_samples, ann_symbols_raw] = rdann(record_path, 'atr');

    % Convert annotation symbols to a cell array of single-char strings
    ann_symbols = cellstr(ann_symbols_raw);

    % --- Package into output struct ---
    record = struct();
    record.id          = record_id;
    record.signal      = signal;
    record.fs          = Fs;
    record.ann_samples = ann_samples;
    record.ann_symbols = ann_symbols;

end
