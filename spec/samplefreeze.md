# samplefreeze (Beta)

`samplefreeze.sh` detects unusually long runs of identical or nearly identical decoded sample values, including non-zero frozen samples that silence detectors miss.

Defaults: exact mode, minimum run 20 ms, non-zero floor -80 dBFS. `--near-tolerance X` enables absolute normalized sample-delta tolerance. `--channel N|all` restricts analysis. Digital-zero events are suppressed unless `--include-zero` is supplied.

```bash
bash/samplefreeze.sh recording.wav --min-run-ms 20 --format tsv
bash/samplefreeze.sh recording.wav --near-tolerance 0.0005 --format jsonl
```

Events: `exact_sample_freeze`, `near_sample_freeze`, `zero_flatline`; channel number, sample value and frame count are included. This differs from `railruns`, which looks for near-full-scale runs. Exit 0 clean, 1 review, 2 error.
