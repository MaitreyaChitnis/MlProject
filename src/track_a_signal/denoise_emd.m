function denoised_signal = denoise_emd(signal, fs)
% DENOISE_EMD  EMD denoising with data-driven IMF selection (v2).
%   denoised_signal = denoise_emd(signal, fs)
% Requires Signal Processing Toolbox (emd, meanfreq).
%
% Instead of dropping a fixed number of IMFs, each IMF is kept only if its
% mean (power-weighted) frequency lies inside the ECG band, 0.5-40 Hz.
%   - very high-frequency IMFs (> 40 Hz)  -> muscle/electrode noise, dropped
%   - very low-frequency IMFs (< 0.5 Hz)  -> baseline wander, dropped
% This adapts to each record instead of using one hand-picked rule.

    f_low  = 0.5;   % Hz
    f_high = 40;    % Hz

    imf = emd(signal, 'Display', 0);     % N x K matrix, one IMF per column
    K = size(imf, 2);

    keep = false(1, K);
    for k = 1:K
        f = meanfreq(imf(:, k), fs);
        keep(k) = (f >= f_low) && (f <= f_high);
    end

    if ~any(keep)          % safety net: never return an empty signal
        keep(:) = true;
    end

    denoised_signal = sum(imf(:, keep), 2);
end
