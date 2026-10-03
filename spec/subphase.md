# subphase (Beta)

`subphase.sh` low-passes stereo audio and reports low-frequency correlation/balance problems by time window. It isolates bass/sub behavior from the rest of the stereo image and reports evidence for review rather than declaring a mix wrong.

Runtime: Bash 4.4+, FFmpeg, FFprobe, awk and coreutils.

```bash
bash/subphase.sh mix.wav --crossover-hz 120 --format jsonl
```

Defaults: 120 Hz crossover, 250 ms windows, -55 dBFS active threshold, weak correlation +0.20, negative 0.00, critical -0.50, minimum run target 500 ms, 4 dB balance warning. Mono is rejected unless `--allow-mono` is used.

Events: `weak_sub_correlation`, `negative_sub_correlation`, `critical_sub_correlation`, `sub_balance_imbalance`. Correlation is normalized covariance of left/right samples after equal low-pass filtering; inactive windows are excluded.

Output: text/TSV/JSONL. Exit codes: 0 clean, 1 review findings, 2 error.
