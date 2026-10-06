function [ann_samples, ann_symbols] = read_mitbih_annotations(atr_file)
% READ_MITBIH_ANNOTATIONS  Pure-MATLAB parser for MIT-BIH .atr annotation files.
%   [ann_samples, ann_symbols] = read_mitbih_annotations('data/raw/100.atr')
%
% Implements the standard WFDB "MIT format" annotation encoding, verified
% against PhysioNet's own format documentation (annot.c / annot.5):
%   each 16-bit word = 6-bit code (top bits) + 10-bit data (bottom bits)
%   code 59 = SKIP (long time jump, next 4 bytes encode the interval)
%   code 60 = NUM, 61 = SUB, 62 = CHN  (metadata, not real beats)
%   code 63 = AUX (an attached text string, not a real beat by itself)
%   code 0, data 0 = end of file
%   any other code = a real annotation at the accumulated time

    fid = fopen(atr_file, 'rb');
    if fid == -1
        error('read_mitbih_annotations:FileNotFound', 'Could not open %s', atr_file);
    end
    bytes = fread(fid, Inf, 'uint8=>double');
    fclose(fid);

    n = length(bytes);
    pos = 1;
    time = 0;

    ann_samples = zeros(0,1);
    ann_symbols = cell(0,1);

    code_map = containers.Map('KeyType','double','ValueType','char');
    code_map(1)='N';  code_map(2)='L';  code_map(3)='R';  code_map(4)='a';
    code_map(5)='V';  code_map(6)='F';  code_map(7)='J';  code_map(8)='A';
    code_map(9)='S';  code_map(10)='E'; code_map(11)='j'; code_map(12)='/';
    code_map(13)='Q'; code_map(28)='+'; code_map(34)='e'; code_map(35)='n';
    code_map(38)='f'; code_map(41)='r'; code_map(22)='"';

    while pos <= n-1
        b1 = bytes(pos); b2 = bytes(pos+1); pos = pos+2;
        word = b1 + b2*256;
        code = floor(word/1024);
        data = mod(word,1024);

        if code == 0 && data == 0
            break; % end of file marker
        end

        switch code
            case 59 % SKIP: next 4 bytes encode a long interval (two 16-bit words, high word first)
                hb1 = bytes(pos); hb2 = bytes(pos+1); pos = pos+2;
                lb1 = bytes(pos); lb2 = bytes(pos+1); pos = pos+2;
                highWord = hb1 + hb2*256;
                lowWord  = lb1 + lb2*256;
                skipAmount = highWord*65536 + lowWord;
                time = time + skipAmount;

            case {60, 61, 62} % NUM / SUB / CHN: metadata only, no extra bytes, not a beat
                % intentionally ignored for this project's purposes

            case 63 % AUX: attached text string, not a beat location itself
                strLen = data;
                pos = pos + strLen;
                if mod(strLen,2) == 1
                    pos = pos + 1; % skip padding byte to stay word-aligned
                end

            otherwise % a real annotation
                time = time + data;
                ann_samples(end+1,1) = time; %#ok<AGROW>
                if isKey(code_map, code)
                    ann_symbols{end+1,1} = code_map(code); %#ok<AGROW>
                else
                    ann_symbols{end+1,1} = '?'; % unmapped code - flagged, not silently wrong
                end
        end
    end
end
