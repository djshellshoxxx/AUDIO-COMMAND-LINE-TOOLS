# Research and tool selection

Research date: 2026-10-03 UTC. This is a practical workflow comparison, not proof that no similar program exists. Searches covered official FFmpeg and aubio documentation, Audacity's manual, and public project README files. General operations such as trimming, peak measurement, silence detection, correlation, subtraction, filtering and onset analysis already exist. The value of this repository is in focused combinations, explicit flags, machine-readable reports, modest dependencies, and composable workflows.

Exact-name searches found no audio results for the proposed names in the sampled search results. An empty search result cannot establish worldwide novelty, exclusive branding, or trademark clearance.

## The selected ten Python / JavaScript tools

| Command | Narrow workflow and useful output | Existing overlap and differentiation |
| --- | --- | --- |
| `loopbudget` | Compare a WAV loop's boundary discontinuity and frame length against an explicit BPM, meter, and bar count; show sample rounding and duration error. | LoopAuditioneer evaluates and edits loops. FFmpeg loops and trims audio. This command combines seam evidence with a musical frame budget in one small report. |
| `tailbudget` | Locate last above-threshold activity and calculate how much quiet tail remains; optionally trim a copy while preserving a chosen pad. | FFmpeg silence detection/removal and SoX trimming cover the primitives. |
| `monoledger` | Report time-coded stereo windows with correlation and mono fold-down energy loss. | FFmpeg offers correlation and channel mixing; FinalPass checks channel integrity and downmix consistency. |
| `gapcontext` | Report quiet-run candidates with active flanks, minimum duration, and surrounding context measurements. | aubioquiet and FFmpeg already detect quiet regions. Requiring active neighbors narrows candidate review. |
| `railruns` | Group near-full-scale samples into per-channel bursts and export their frame/time ledger. | FFmpeg astats reports peak-related statistics. |
| `dcjourney` | Calculate windowed channel means and the global mean in an offset timeline. | FFmpeg astats measures DC offset and dcshift changes it. |
| `gainbudget` | Calculate per-channel sample-peak headroom for requested gain and ceiling; optionally write a bounded-gain copy. | FFmpeg volume and statistics already support gain and peaks. |
| `stemcontract` | Validate a set of named WAV stems against explicit rate, channels, frame count and filename requirements. | FinalPass provides broader post-production delivery QC. |
| `cueclock` | Generate a musical cue grid as integer sample positions and show timing-rounding drift for user-supplied tempo and meter. | aubio estimates beats; LoopAuditioneer handles cue metadata. This tool generates arithmetic positions rather than detecting beats. |
| `renderdelta` | Compare two compatible renders with explicit offset and output residual-energy windows plus an optional difference WAV. | Google audio-sync-kit performs broader synchronization/reference analysis; FinalPass includes null checks. |

## Bash-native pipeline family

The Bash family was selected separately from the original ten. The requirement was not to wrap Python, but to create utilities whose value comes from Unix composition and ordinary FFmpeg/FFprobe primitives. Searches and documentation review did not identify a well-established standalone command with the same narrow end-to-end workflow for each item below. That does not establish that no comparable implementation exists.

| Command | Gap targeted | Existing primitives / distinction |
| --- | --- | --- |
| `edgeguard` | Review whether a render appears to start/end hard at the file boundary rather than with silence/fade evidence. | FFmpeg exposes trimming, fade and statistics primitives, but the tool combines boundary RMS, endpoint discontinuity and short envelope behavior into one review ledger. |
| `subphase` | Timestamp low-frequency-only stereo correlation and balance issues independently from higher-frequency width. | Correlation meters and FFmpeg correlation/filtering exist. The distinction is the dedicated crossover-limited, scriptable event ledger. |
| `banddrift` | Find sections whose tonal balance moves materially away from the same file's normal distribution. | Spectral analyzers and reference EQ tools exist. This tool reports relative per-band energy-share drift for piping and batch review rather than recommending EQ. |
| `repeataudit` | Find exact decoded PCM blocks repeated by capture/buffer faults or accidental duplication. | Checksums and audio editors provide the underlying pieces. This utility aligns decoding, block hashing, grouping and timestamps in one pipeline-oriented command. |
| `samplefreeze` | Find long runs where sample values remain exactly or nearly unchanged, including non-zero values. | Silence and clipping detectors overlap only partially. This differs from silence detection and from this repo's `railruns`, which targets near-full-scale runs. |
| `transientledger` | Compare transient density and crest-factor regimes across a file without opening a DAW. | Onset detectors and statistics tools exist. This tool combines envelope-rise counts, density and crest behavior into relative time-coded review events. |

The Bash tools therefore should be described as original implementations of specialized composed workflows, not as six categories that have never existed before.

## Primary sources reviewed

1. [FFmpeg filter documentation](https://ffmpeg.org/ffmpeg-filters.html), opened 2026-10-03. Relevant primitives include `astats`, `silencedetect`, `silenceremove`, `atrim`, `afade`, `highpass`, `lowpass`, `axcorrelate`, `pan`, `dcshift`, `volume`, `aloop` and general raw PCM output. These establish substantial primitive-level overlap and support the choice to focus on compositions rather than generic DSP commands.
2. [FFprobe documentation](https://ffmpeg.org/ffprobe.html), opened 2026-10-03. Machine-readable stream inspection supplies sample rate/channel metadata and validates decodable input for the Bash tools.
3. [aubio command-line documentation](https://aubio.org/manual/latest/cli.html), opened 2026-10-03. Existing programs extract onset, pitch, beats, note descriptors, and quiet/loud regions; generic onset, beat, silence and pitch tools were therefore excluded.
4. [Audacity editing FAQ](https://manual.audacityteam.org/man/faq_editing.html), opened 2026-10-03. It documents practical zero-crossing considerations and why endpoint discontinuity alone is not a complete perceptual judgment.
5. [LoopAuditioneer README](https://github.com/GrandOrgue/LoopAuditioneer), opened 2026-10-03. It documents loop/cue evaluation, crossfading, metadata editing and batch preparation.
6. [FinalPass README](https://github.com/alexeymohr/FinalPass), opened 2026-10-03. It describes delivery QC including loudness, null tests, channel integrity and downmix consistency.
7. [Google audio-sync-kit README](https://github.com/google/audio-sync-kit), opened 2026-10-03. Reference/actual comparisons can report offsets and dropout intervals; simple decoded-block comparison does not replace that broader synchronization analysis.
8. [MDN decodeAudioData documentation](https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData), opened 2026-10-03. Browser decoding can resample, which is why source-frame-accurate browser tools parse WAV explicitly while the Bash family deliberately delegates decoding to FFmpeg.

## Engineering limits derived from the comparison

The tools report evidence to inspect rather than conclusions about creative intent, mastering quality, corruption cause, or encoding provenance. A hard boundary can be intentional. Negative low-band correlation can be intentional. Tonal shifts can be arrangement changes. Exact repeated audio can be legitimate material. Constant samples can be synthetic audio. Transient-density changes can be musical structure.

Analyze channels independently where summing could hide behavior through cancellation. Exclude inactive windows from normalized correlation and relative medians. Keep timeline ranges deterministic and end-exclusive where practical. Use a locale-independent decimal format in Bash output. Never overwrite or modify input audio.

The Bash family decodes through FFmpeg to canonical PCM for analysis. This broadens codec support compared with the original direct-WAV engine but means measurements reflect FFmpeg's decoded representation. Exact block repetition refers to that decoded representation, not necessarily byte-for-byte identity of compressed source packets.

The intended Unix model is transparent composition: the programs produce text, TSV or JSONL that can be filtered with `awk`, `grep`, `sort`, `xargs` and optional `jq`. Python remains a test harness only and is not a runtime dependency of the Bash tools.
