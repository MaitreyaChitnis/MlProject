function denoised_signal = denoise_highpass_cut(signal, fs, fc)
% DENOISE_HIGHPASS_CUT  High-pass filter with a chosen cutoff (Hz), zero phase.
%   denoised_signal = denoise_highpass_cut(signal, fs, fc)
% Used for the cutoff sweep: how does the classification result change as the
% cutoff moves from 0.05 Hz up to 0.5 Hz? No low-pass, no notch.

    hp = designfilt('highpassiir', ...
        'FilterOrder', 4, ...
        'HalfPowerFrequency', fc, ...
        'SampleRate', fs);
    denoised_signal = filtfilt(hp, signal);
end
