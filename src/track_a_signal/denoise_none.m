function denoised_signal = denoise_none(signal, fs)
% DENOISE_NONE  Baseline/control: returns the signal completely unchanged.
%   denoised_signal = denoise_none(signal, fs)
% fs is accepted but unused here, kept only so all denoise_*.m functions
% share the exact same input/output shape and can be swapped interchangeably.
    denoised_signal = signal;
end
