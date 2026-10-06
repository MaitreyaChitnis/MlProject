function denoised_signal = denoise_emd(signal, fs)
% DENOISE_EMD  Empirical Mode Decomposition based denoising.
%   denoised_signal = denoise_emd(signal, fs)
% Requires Signal Processing Toolbox (emd function). fs accepted but unused.
%
% Drops the first 2 IMFs (usually high-frequency noise) and the last IMF
% (usually baseline wander / residual trend), keeps the middle IMFs.
% TUNE THESE NUMBERS by visually inspecting a few records - the right
% number to drop can vary record to record.

    imf = emd(signal, 'Display', 0);
    num_imfs = size(imf, 2);

    drop_first = 2;  % high-frequency noise IMFs to drop
    drop_last = 1;   % baseline wander IMF to drop

    keep_idx = (drop_first+1):(num_imfs-drop_last);
    if isempty(keep_idx)
        keep_idx = 1:num_imfs; % fallback safety net if too few IMFs
    end

    denoised_signal = sum(imf(:, keep_idx), 2);
end
