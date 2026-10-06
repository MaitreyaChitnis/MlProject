function denoised_signal = denoise_wavelet(signal, fs)
% DENOISE_WAVELET  Wavelet-threshold denoising using MATLAB's wdenoise.
%   denoised_signal = denoise_wavelet(signal, fs)
% Requires Wavelet Toolbox. fs is accepted but unused (wdenoise works
% directly on samples), kept for interface consistency with other tracks.

    denoised_signal = wdenoise(signal, 'Wavelet', 'sym4', ...
        'DenoisingMethod', 'Bayes', ...
        'ThresholdRule', 'Soft');
end
