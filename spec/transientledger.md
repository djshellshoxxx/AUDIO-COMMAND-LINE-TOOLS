# transientledger (Beta)

`transientledger.sh` reports changes in transient density and crest factor over time. It is useful for locating sections whose transient character differs from the rest of the same file; it does not label material over- or under-compressed.

The script decodes a mono analysis stream, measures RMS/peak per analysis window, builds a shorter RMS envelope, counts positive envelope rises separated by a minimum spacing, and compares density/crest values with active-window medians.

Defaults: 2 s windows, 10 ms envelope, +6 dB rise, 30 ms spacing, -60 dBFS active threshold, 60% density deviation, 6 dB crest deviation.

```bash
bash/transientledger.sh mix.wav --format jsonl
```

Events: `transient_density_low`, `transient_density_high`, `crest_factor_low`, `crest_factor_high`. Output is text/TSV/JSONL; 0 clean, 1 review, 2 error.
