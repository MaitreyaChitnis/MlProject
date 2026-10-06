function peak_locations = detect_rpeaks_pantompkins(signal, fs)
% DETECT_RPEAKS_PANTOMPKINS  Simplified Pan-Tompkins R-peak detector.
%   peak_locations = detect_rpeaks_pantompkins(signal, fs)
% Returns a column vector of sample indices where R-peaks were detected.

    % 1. Bandpass filter (5-15 Hz emphasizes the QRS complex)
    bp = designfilt('bandpassiir', ...
        'FilterOrder', 4, ...
        'HalfPowerFrequency1', 5, ...
        'HalfPowerFrequency2', 15, ...
        'SampleRate', fs);
    filtered = filtfilt(bp, signal);

    % 2. Derivative (emphasizes steep slopes, which QRS complexes have)
    derivative = diff(filtered);
    derivative = [derivative; 0]; % pad back to original length

    % 3. Squaring (makes everything positive, exaggerates large slopes further)
    squared = derivative .^ 2;

    % 4. Moving window integration (~150ms window, smooths spike into a hump)
    window_size = round(0.150 * fs);
    integrated = movmean(squared, window_size);

    % 5. Simple threshold-based peak picking.
    % MinPeakDistance enforces a minimum physiological gap between beats
    % (200ms = faster than 300 bpm, prevents double-counting one beat).
    min_distance = round(0.2 * fs);
    min_height = 0.3 * max(integrated);

    [~, peak_locations] = findpeaks(integrated, ...
        'MinPeakHeight', min_height, ...
        'MinPeakDistance', min_distance);
end
