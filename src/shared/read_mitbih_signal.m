function signal = read_mitbih_signal(dat_file, info)
% READ_MITBIH_SIGNAL  Pure-MATLAB reader for MIT-BIH format-212 .dat files.
%   signal = read_mitbih_signal('data/raw/100.dat', info)
% 'info' is the struct returned by parse_mitbih_header.m
%
% Returns signal as [nSamples x nSignals] in PHYSICAL units (already
% converted using each signal's gain/baseline from the header).
%
% NOTE: this function assumes format 212 with exactly 2 signals sharing
% one file, which covers the large majority of standard MIT-BIH records.
% If you hit a record that errors here, tell me and I'll extend it.

    if info.signals(1).format ~= 212
        error('read_mitbih_signal:UnsupportedFormat', ...
            'This reader only supports format 212 (got format %d). Ask for an extended version.', ...
            info.signals(1).format);
    end
    if info.nSignals ~= 2
        error('read_mitbih_signal:UnsupportedChannelCount', ...
            'This reader assumes exactly 2 signals sharing one file (got %d). Ask for an extended version.', ...
            info.nSignals);
    end

    fid = fopen(dat_file, 'rb');
    if fid == -1
        error('read_mitbih_signal:FileNotFound', 'Could not open %s', dat_file);
    end
    raw_bytes = fread(fid, Inf, 'uint8=>double');
    fclose(fid);

    % Format 212: every 3 bytes encode 2 twelve-bit samples (one per channel)
    nTriplets = floor(length(raw_bytes) / 3);
    raw_bytes = raw_bytes(1 : nTriplets*3);
    b1 = raw_bytes(1:3:end);
    b2 = raw_bytes(2:3:end);
    b3 = raw_bytes(3:3:end);

    s1 = b1 + 256 * mod(b2, 16);          % low nibble of b2 = high bits of sample 1
    s2 = b3 + 256 * floor(b2 / 16);       % high nibble of b2 = high bits of sample 2

    s1(s1 > 2047) = s1(s1 > 2047) - 4096; % sign-extend 12-bit two's complement
    s2(s2 > 2047) = s2(s2 > 2047) - 4096;

    raw_ch1 = s1;
    raw_ch2 = s2;

    gain1 = info.signals(1).gain; base1 = info.signals(1).baseline;
    gain2 = info.signals(2).gain; base2 = info.signals(2).baseline;

    ch1 = (raw_ch1 - base1) / gain1;
    ch2 = (raw_ch2 - base2) / gain2;

    signal = [ch1, ch2];

    if ~isnan(info.nSamples) && size(signal,1) > info.nSamples
        signal = signal(1:info.nSamples, :); % trim any trailing padding
    end
end
