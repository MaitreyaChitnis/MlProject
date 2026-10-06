function [sensitivity, positive_predictivity] = validate_detection(detected_peaks, true_peaks, fs)
% VALIDATE_DETECTION  Compare detected R-peaks against ground-truth annotations.
%   [sensitivity, positive_predictivity] = validate_detection(detected_peaks, true_peaks, fs)
%
% Uses a +/- 50ms tolerance window: a detected peak counts as correct (a
% true positive) if it falls within 50ms of some annotated true peak, and
% each true peak can only be matched to one detected peak.

    tolerance_samples = round(0.050 * fs);

    matched_true = false(size(true_peaks));
    true_positives = 0;

    for i = 1:length(detected_peaks)
        diffs = abs(true_peaks - detected_peaks(i));
        [min_diff, idx] = min(diffs);
        if min_diff <= tolerance_samples && ~matched_true(idx)
            true_positives = true_positives + 1;
            matched_true(idx) = true;
        end
    end

    false_negatives = sum(~matched_true);
    false_positives = length(detected_peaks) - true_positives;

    sensitivity = true_positives / (true_positives + false_negatives);
    positive_predictivity = true_positives / (true_positives + false_positives);
end
