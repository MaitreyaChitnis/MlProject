D = load('data/processed/features_ds1_ds2.mat'); test = D.test; train = D.train;
nS = accumarray(test.row_record, double(test.y(:)=='S'));
[~,k] = max(nS);  rows = test.row_record==k;
r = test.X(rows,1) ./ test.X(rows,3);
isS = test.y(rows)=='S';
fprintf('Top-S record %s: median RR_local_avg = %.2f s (DS2 overall %.2f, DS1 %.2f)\n', ...
    test.record_ids{k}, median(test.X(rows,3)), median(test.X(:,3)), median(train.X(:,3)));
fprintf('S beats there arriving early: %.1f %%\n', 100*mean(r(isS) < 0.85));