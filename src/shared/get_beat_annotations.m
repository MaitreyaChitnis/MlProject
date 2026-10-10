function [beat_samples, beat_aami, beat_symbols, info] = get_beat_annotations(record)
%GET_BEAT_ANNOTATIONS  Return BEAT annotations only (non-beat markers removed).
%
%   [beat_samples, beat_aami, beat_symbols, info] = get_beat_annotations(record)
%
%   INPUT
%     record        struct from load_record(id). Uses record.ann_samples,
%                   record.ann_symbols, record.signal and record.id.
%
%   OUTPUT
%     beat_samples  column vector of beat sample indices (same index
%                   convention as record.ann_samples, unchanged).
%     beat_aami     cell column of AAMI labels: 'N' | 'S' | 'V' | 'F' | 'Q'.
%     beat_symbols  cell column of the original MIT-BIH beat symbols
%                   (kept for the S-class confusion analysis in Stage 5).
%     info          struct with counts and masks (see below).
%
%   BEAT SYMBOLS KEPT (AAMI EC57 mapping)
%     N: N L R e j     S: A a J S     V: V E     F: F     Q: / f Q
%
%   Everything else is dropped. That includes:
%     '+' rhythm change, '"' comment, '~' signal-quality change,
%     '|' isolated QRS-like artefact, 'x' non-conducted P wave,
%     '!' ventricular flutter wave, '[' and ']' flutter start and end,
%     and '?', which read_mitbih_annotations writes for codes it
%     cannot map.
%   This is a WHITELIST: a symbol is kept only if it is in the list
%   above. So any unexpected code is removed and reported in info,
%   never silently labelled 'Q'.
%
%   info FIELDS
%     record_id        record.id (if present)
%     n_total          number of annotations of any kind
%     n_beats          number of beat annotations kept
%     n_removed        n_total - n_beats
%     is_beat          logical mask aligned with record.ann_samples
%     all_symbols      cleaned cell column of ALL symbols (aligned with mask)
%     removed_symbols  cell column of the distinct removed symbols
%     removed_counts   count for each entry of removed_symbols
%     class_counts     struct with fields N, S, V, F and Q (beat counts)
%
%   NOTE: map_symbol_to_aami is NOT modified (its interface is frozen).
%   It only ever receives whitelisted beat symbols from this function, so
%   its "fallback to Q" branch can no longer be reached.

BEAT_SYMBOLS = {'N','L','R','e','j', ...   % N class
                'A','a','J','S', ...       % S class (SVEB)
                'V','E', ...               % V class (VEB)
                'F', ...                   % F class
                '/','f','Q'};              % Q class
AAMI_CLASSES = {'N','S','V','F','Q'};

%% --- read and clean the inputs ---
samples = double(record.ann_samples(:));

symbols = record.ann_symbols;
if isstring(symbols) || ischar(symbols)
    symbols = cellstr(symbols);
end
symbols = symbols(:);
symbols = cellfun(@(s) strtrim(char(s)), symbols, 'UniformOutput', false);

if numel(samples) ~= numel(symbols)
    error('get_beat_annotations:sizeMismatch', ...
        'Record %s: %d annotation samples but %d symbols.', ...
        local_id(record), numel(samples), numel(symbols));
end

%% --- keep beat annotations only ---
is_beat      = ismember(symbols, BEAT_SYMBOLS);
beat_samples = samples(is_beat);
beat_symbols = symbols(is_beat);

if isempty(beat_symbols)
    beat_aami = cell(0, 1);
else
    beat_aami = cellfun(@(s) char(map_symbol_to_aami(s)), beat_symbols, ...
                        'UniformOutput', false);
end

%% --- sanity checks ---
bad = ~ismember(beat_aami, AAMI_CLASSES);
if any(bad)
    error('get_beat_annotations:badLabel', ...
        'Record %s: map_symbol_to_aami returned an unknown label for symbol ''%s''.', ...
        local_id(record), beat_symbols{find(bad, 1)});
end

if ~issorted(beat_samples)
    warning('get_beat_annotations:unsorted', ...
        'Record %s: beat annotations were not in time order; sorting them.', local_id(record));
    [beat_samples, order] = sort(beat_samples);
    beat_symbols = beat_symbols(order);
    beat_aami    = beat_aami(order);
end

n_dup = numel(beat_samples) - numel(unique(beat_samples));
if n_dup > 0
    warning('get_beat_annotations:duplicates', ...
        'Record %s: %d beat annotations share a sample index with another beat.', ...
        local_id(record), n_dup);
end

if isfield(record, 'signal')
    n_sig = size(record.signal, 1);
    n_out = sum(beat_samples < 0 | beat_samples > n_sig);
    if n_out > 0
        warning('get_beat_annotations:outOfRange', ...
            'Record %s: %d beat annotations lie outside the signal (1..%d).', ...
            local_id(record), n_out, n_sig);
    end
end

%% --- bookkeeping ---
removed = symbols(~is_beat);
if isempty(removed)
    removed_symbols = cell(0, 1);
    removed_counts  = zeros(0, 1);
else
    [removed_symbols, ~, ic] = unique(removed);
    removed_symbols = removed_symbols(:);
    removed_counts  = accumarray(ic(:), 1, [numel(removed_symbols), 1]);
end

info = struct();
info.record_id       = local_id(record);
info.n_total         = numel(symbols);
info.n_beats         = numel(beat_samples);
info.n_removed       = info.n_total - info.n_beats;
info.is_beat         = is_beat;
info.all_symbols     = symbols;
info.removed_symbols = removed_symbols;
info.removed_counts  = removed_counts;
for k = 1:numel(AAMI_CLASSES)
    info.class_counts.(AAMI_CLASSES{k}) = sum(strcmp(beat_aami, AAMI_CLASSES{k}));
end
end

%% ------------------------------------------------------------------------
function s = local_id(record)
% Record id as text, for messages.
if isfield(record, 'id')
    s = char(string(record.id));
else
    s = '?';
end
end
