function [features, labels, beat_samples] = extract_features(record, lead, half_window, n_avg)
% EXTRACT_FEATURES  Build a per-beat feature matrix and AAMI label vector.
%
%   [features, labels, beat_samples] = extract_features(record)
%   [features, labels, beat_samples] = extract_features(record, lead, half_window, n_avg)
%
% INPUT
%   record      : struct from load_record.m (needs .signal, .fs,
%                 .ann_samples, .ann_symbols)
%   lead        : (optional) which signal column to use. Default 1.
%   half_window : (optional) samples taken on each side of the R-peak.
%                 Default 90 (window = 90 before + R-peak + 90 after = 181).
%   n_avg       : (optional) how many recent RR intervals go into
%                 RR_local_avg. Default 10.
%
% OUTPUT
%   features     : [nBeats x (3 + 2*half_window + 1)]
%                  columns = [RR_prev, RR_next, RR_local_avg, morphology...]
%                  RR values are in SECONDS.
%   labels       : [nBeats x 1] char column of AAMI classes (N,S,V,F,Q),
%                  produced by map_symbol_to_aami.m
%   beat_samples : [nBeats x 1] original sample index of each kept beat
%
% NOTES
%   * Non-beat annotations (e.g. '+', '"', '~', '?') are removed FIRST, so
%     RR intervals are always between real beats.
%   * The first and last beat are skipped (no previous/next RR). Beats
%     whose window would run past the signal edges are skipped too.
%   * RR_local_avg = mean of the last n_avg RR intervals ending at RR_prev
%     (uses fewer than n_avg at the very start of a record).

    if nargin < 2 || isempty(lead),        lead = 1;         end
    if nargin < 3 || isempty(half_window), half_window = 90; end
    if nargin < 4 || isempty(n_avg),       n_avg = 10;       end

    n_morph = 2*half_window + 1;

    % Empty outputs with the correct shape (used for early returns)
    features     = zeros(0, 3 + n_morph);
    labels       = char(zeros(0, 1));
    beat_samples = zeros(0, 1);

    % --- 1. keep only real heartbeat annotations ---
    beat_symbols = {'N','L','R','a','V','F','J','A','S','E', ...
                    'j','/','Q','e','n','f','r'};
    samp = record.ann_samples(:);
    sym  = record.ann_symbols(:);
    is_beat = ismember(sym, beat_symbols);
    samp = samp(is_beat);
    sym  = sym(is_beat);

    nB = numel(samp);
    if nB < 3
        return; % not enough beats to have a beat with both neighbours
    end

    fs = record.fs;
    x  = record.signal(:, lead);
    nSamples = numel(x);

    % rr(k) = time (s) between beat k and beat k+1  -> length nB-1
    rr = diff(samp) / fs;

    % --- 2. loop over every beat except first and last ---
    feats = nan(nB-2, 3 + n_morph);
    labs  = repmat('Q', nB-2, 1);
    samps = zeros(nB-2, 1);
    keep  = false(nB-2, 1);

    for i = 2:(nB-1)
        r = samp(i);
        if r - half_window < 1 || r + half_window > nSamples
            continue; % window would fall off the signal
        end

        rr_prev = rr(i-1);
        rr_next = rr(i);
        rr_avg  = mean(rr(max(1, i-n_avg) : i-1));

        morph = x(r-half_window : r+half_window).';  % row vector

        k = i - 1;
        feats(k, :) = [rr_prev, rr_next, rr_avg, morph];
        labs(k)     = map_symbol_to_aami(sym{i});
        samps(k)    = r;
        keep(k)     = true;
    end

    features     = feats(keep, :);
    labels       = labs(keep);
    beat_samples = samps(keep);
end
