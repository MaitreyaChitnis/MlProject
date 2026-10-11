function denoised_signal = denoise_highpass(signal, fs)
% DENOISE_HIGHPASS  Diagnostic variant: ONLY removes content below 0.5 Hz
% (baseline wander and DC level). No low-pass, no notch.
%   denoised_signal = denoise_highpass(signal, fs)
% Used to find out whether the drop seen with 'bandpass' and 'emd' comes
% from removing the slow components.

    hp = designfilt('highpassiir', ...
        'FilterOrder', 4, ...
        'HalfPowerFrequency', 0.5, ...
        'SampleRate', fs);
    denoised_signal = filtfilt(hp, signal);
end
