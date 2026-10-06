function info = parse_mitbih_header(hea_file)
% PARSE_MITBIH_HEADER  Pure-MATLAB parser for a MIT-BIH .hea header file.
%   info = parse_mitbih_header('data/raw/100.hea')
%
% Returns a struct:
%   info.recordName, info.nSignals, info.fs, info.nSamples
%   info.signals(k).filename, .format, .gain, .baseline, .description

    fid = fopen(hea_file, 'r');
    if fid == -1
        error('parse_mitbih_header:FileNotFound', 'Could not open %s', hea_file);
    end

    % --- First (record) line ---
    line1 = strtrim(fgetl(fid));
    tokens = strsplit(line1);
    info.recordName = tokens{1};
    info.nSignals = str2double(tokens{2});
    fsToken = strsplit(tokens{3}, '/'); % handles "360" or "360/1" style
    info.fs = str2double(fsToken{1});
    if numel(tokens) >= 4
        info.nSamples = str2double(tokens{4});
    else
        info.nSamples = NaN;
    end

    % --- One line per signal ---
    info.signals = struct('filename', {}, 'format', {}, 'gain', {}, ...
                           'baseline', {}, 'description', {});
    for k = 1:info.nSignals
        line = strtrim(fgetl(fid));
        t = strsplit(line);

        filename = t{1};
        formatStr = regexp(t{2}, '^\d+', 'match', 'once');
        format = str2double(formatStr);

        gainField = t{3};
        baseline = 0; % default if not specified
        gainNumStr = gainField;
        if contains(gainField, '(')
            inside = regexp(gainField, '\(([^)]+)\)', 'tokens', 'once');
            baseline = str2double(inside{1});
            gainNumStr = extractBefore(gainField, '(');
        end
        if contains(gainNumStr, '/')
            parts = strsplit(gainNumStr, '/');
            gainNumStr = parts{1};
        end
        gain = str2double(gainNumStr);
        if gain == 0 || isnan(gain)
            gain = 200; % MIT-BIH default fallback
        end

        % Standard field order: filename format gain adcres adczero firstval checksum blocksize description
        adczero = baseline; % overwritten below if an explicit ADCZero field exists
        if numel(t) >= 5
            maybeZero = str2double(t{5});
            if ~isnan(maybeZero)
                adczero = maybeZero;
            end
        end

        description = '';
        if numel(t) >= 9
            description = strjoin(t(9:end), ' ');
        elseif numel(t) >= 1
            description = '';
        end

        info.signals(k).filename = filename;
        info.signals(k).format = format;
        info.signals(k).gain = gain;
        info.signals(k).baseline = adczero;
        info.signals(k).description = description;
    end

    fclose(fid);
end
