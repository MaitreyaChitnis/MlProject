function denoised_signal = denoise_lowpass(signal, fs)
% DENOISE_LOWPASS  Diagnostic variant: ONLY removes content above 40 Hz
% (muscle noise and fast detail). No high-pass, no notch.
%   denoised_signal = denoise_lowpass(signal, fs)
% Used to find out whether the drop seen with 'bandpass' and 'emd' comes
% from smoothing the fast components.

    lp = designfilt('lowpassiir', ...
        'FilterOrder', 4, ...
        'HalfPowerFrequency', 40, ...
        'SampleRate', fs);
    denoised_signal = filtfilt(lp, signal);
end
