function peak_locations = detect_rpeaks_pantompkins(signal, fs)
% DETECT_RPEAKS_PANTOMPKINS  Pan-Tompkins R-peak detector (v4):
% adaptive thresholds (running signal/noise peak estimates) + search-back.
%
%   peak_locations = detect_rpeaks_pantompkins(signal, fs)
% Returns a column vector of sample indices of detected R-peaks.

    persistent announced
    if isempty(announced)
        fprintf('[detect_rpeaks_pantompkins] Running v4: adaptive threshold + search-back\n');
        announced = true;
    end

    % 1. Bandpass (5-15 Hz emphasizes the QRS complex)
    bp = designfilt('bandpassiir', 'FilterOrder', 4, ...
        'HalfPowerFrequency1', 5, 'HalfPowerFrequency2', 15, 'SampleRate', fs);
    filtered = filtfilt(bp, signal);

    % 2. Derivative
    derivative = [diff(filtered); 0];

    % 3. Squaring
    squared = derivative .^ 2;

    % 4. Moving-window integration (~150 ms)
    integrated = movmean(squared, round(0.150 * fs));

    % 5. Candidate peaks (200 ms refractory period)
    min_distance = round(0.2 * fs);
    [peak_vals, peak_locs] = findpeaks(integrated, 'MinPeakDistance', min_distance);

    peak_locations = zeros(0,1);
    if isempty(peak_locs)
        return;
    end

    % Initial running estimates from the first 2 seconds
    init_window = min(round(2*fs), length(integrated));
    init_max = max(integrated(1:init_window));
    SPKI = 0.5 * init_max;   % running "signal peak" level
    NPKI = 0.1 * init_max;   % running "noise peak" level

    last_loc = NaN;          % location of last accepted beat
    last_k   = 0;            % candidate index of last accepted beat
    rr_hist  = [];           % last accepted RR intervals (samples)

    for k = 1:numel(peak_vals)
        pk  = peak_vals(k);
        loc = peak_locs(k);

        thr1 = NPKI + 0.25 * (SPKI - NPKI);
        thr2 = 0.5 * thr1;   % lower threshold used only for search-back

        % --- Search-back: too long since last beat? Re-check skipped candidates ---
        if ~isempty(rr_hist) && (loc - last_loc) > 1.66 * mean(rr_hist)
            cand = (last_k+1):(k-1);
            cand = cand(peak_vals(cand) > thr2);
            if ~isempty(cand)
                [~, m] = max(peak_vals(cand));
                j = cand(m);
                peak_locations(end+1,1) = peak_locs(j); %#ok<AGROW>
                SPKI = 0.25 * peak_vals(j) + 0.75 * SPKI;
                rr_hist(end+1) = peak_locs(j) - last_loc; %#ok<AGROW>
                rr_hist = rr_hist(max(1,end-7):end);
                last_loc = peak_locs(j);
                last_k = j;
            end
        end

        % --- Normal classification of the current candidate ---
        if pk > thr1
            peak_locations(end+1,1) = loc; %#ok<AGROW>
            % Cap the influence of one huge peak (e.g. a PVC) on SPKI
            pk_capped = min(pk, 3 * SPKI);
            SPKI = 0.125 * pk_capped + 0.875 * SPKI;
            if ~isnan(last_loc)
                rr_hist(end+1) = loc - last_loc; %#ok<AGROW>
                rr_hist = rr_hist(max(1,end-7):end);
            end
            last_loc = loc;
            last_k = k;
        else
            NPKI = 0.125 * pk + 0.875 * NPKI;
        end
    end
end
