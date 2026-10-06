function aami_class = map_symbol_to_aami(symbol)
% MAP_SYMBOL_TO_AAMI  Convert one MIT-BIH annotation symbol to its AAMI EC57 class.
%
%   aami_class = map_symbol_to_aami('N')   returns 'N'
%   aami_class = map_symbol_to_aami('V')   returns 'V'
%
% Both Track A and Track B must use this exact function - do not write
% a second version anywhere else in the codebase.

    switch symbol
        case {'N','L','R','e','j'}
            aami_class = 'N';
        case {'A','a','J','S'}
            aami_class = 'S';
        case {'V','E'}
            aami_class = 'V';
        case {'F'}
            aami_class = 'F';
        case {'/','f','Q'}
            aami_class = 'Q';
        otherwise
            aami_class = 'Q'; % unknown/unclassified symbols fall back to Q
    end
end
