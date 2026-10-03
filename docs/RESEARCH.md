# Research and tool selection

Research date: 2026-10-03 UTC. This is a practical workflow comparison, not proof that no similar program exists. Searches covered official FFmpeg and aubio documentation, Audacity's manual, and public project README files. General operations such as trimming, peak measurement, silence detection, correlation, loudness measurement and subtraction already exist. The value of this repository is in focused combinations, explicit flags, machine-readable reports, modest dependencies, and repeatable automation.

Exact-name searches cannot establish worldwide novelty. The tools should be described as original implementations of selected workflows rather than previously nonexistent DSP categories.

## The original ten

| Command | Narrow workflow and useful output | Existing overlap and differentiation |
| --- | --- | --- |
| `loopbudget` | Compare a WAV loop's boundary discontinuity and frame length against an explicit BPM, meter, and bar count; show sample rounding and duration error. | LoopAuditioneer evaluates and edits loops. FFmpeg loops and trims audio. This command combines seam evidence with a musical frame budget in one small report. |
| `tailbudget` | Locate last above-threshold activity and calculate how much quiet tail remains; optionally trim a copy while preserving a chosen pad. | FFmpeg silence detection/removal and SoX trimming cover the primitives. A keep-pad budget and explicit before/after frame accounting make the export decision clear. |
| `monoledger` | Report time-coded stereo windows with correlation and mono fold-down energy loss. | FFmpeg offers correlation and channel mixing; FinalPass checks channel integrity and downmix consistency. The focused ledger locates specific windows. |
| `gapcontext` | Report quiet-run candidates with active flanks, minimum duration, and surrounding context measurements. | aubioquiet and FFmpeg already detect quiet regions. Requiring active neighbors narrows candidate review. |
| `railruns` | Group near-full-scale samples into per-channel bursts and export their frame/time ledger. | FFmpeg astats reports peak-related statistics. This emphasizes burst positions and consecutive-run lengths. |
| `dcjourney` | Calculate windowed channel means and the global mean in an offset timeline. | FFmpeg astats measures DC offset and dcshift changes it. The difference is the compact temporal journey. |
| `gainbudget` | Calculate per-channel sample-peak headroom for requested gain and ceiling; optionally write a bounded-gain copy. | FFmpeg volume and statistics already support gain and peaks. This workflow explains requested versus available gain before exporting. |
| `stemcontract` | Validate a set of named WAV stems against explicit rate, channels, and frame-count requirements. | FinalPass provides broader post-production delivery QC. This is a smaller contract validator for a specific handoff. |
| `cueclock` | Generate a musical cue grid as integer sample positions and show timing-rounding drift for user-supplied tempo and meter. | aubio estimates beat positions from audio; LoopAuditioneer handles WAV cue metadata. This generates a deterministic arithmetic grid. |
| `renderdelta` | Compare two compatible renders with explicit offset and output residual-energy windows plus an optional difference WAV. | Google audio-sync-kit compares reference/actual audio and reports synchronization/dropout evidence; FinalPass includes stem-sum null checks. This is a smaller offset-aware residual ledger. |

## Shell-native gap pass

The top-level `bash/` and `powershell/` tools address a different gap from the original Python/JavaScript suite. FFmpeg and FFprobe already expose the required measurements, but many practical QC questions still require several commands, log parsing, threshold logic and batch aggregation. The shell-native tools package those workflows directly for automation without calling Python or JavaScript at runtime.

| Command | Workflow gap | FFmpeg/FFprobe primitives used |
| --- | --- | --- |
| `stereotruth` | Quickly identify stereo files that behave like dual-mono, strongly negative correlation, or sustained channel imbalance. | `aphasemeter`, `ametadata`, `astats`, FFprobe channel metadata |
| `loudwalk` | Turn verbose EBU R128 output into a time-coded internal-consistency report. | `ebur128` |
| `formattruth` | Convert FFprobe's raw format/stream facts into concise extension/container/stream consistency findings. | FFprobe stream and format queries |
| `albumcontract` | Infer or enforce a technical contract across a directory and expose accidental outliers. | FFprobe metadata, optional `ebur128` |
| `phasewatch` | Preserve a timestamped stereo correlation ledger instead of one whole-file statistic. | `aphasemeter`, `ametadata` |
| `batchsilence` | Compare leading/trailing silence across an export set rather than trimming one file at a time. | `silencedetect`, FFprobe duration |
| `transcodeaudit` | Triage codec/container/bitrate/encoder combinations for manual provenance review without claiming to prove encoding history. | FFprobe format/stream/tag queries |

These additions intentionally use FFmpeg as the DSP engine. Reimplementing correlation, loudness or decoding in shell would be less reliable and would add no useful differentiation. The Bash and PowerShell implementations instead own argument parsing, deterministic discovery, aggregation, policy thresholds, normalized JSON/text reports and exit-code semantics.

The previous `python/drift-audio.sh`, `.ps1`, and `.cmd` files remain launchers for the Python engine and should still be described that way. The new top-level `bash/` and `powershell/` directories are independent shell-native orchestration tools with FFmpeg/FFprobe as their runtime dependencies.

## Primary sources reviewed

1. [FFmpeg filter documentation](https://ffmpeg.org/ffmpeg-filters.html), opened 2026-10-03. Relevant documented primitives include `astats`, `aphasemeter`, `ametadata`, `ebur128`, `silencedetect`, `silenceremove`, `atrim`, `apad`, `axcorrelate`, `pan`, `dcshift`, `volume`, and `aloop`. A composed FFmpeg pipeline can reproduce many individual operations; the repository's differentiation is workflow composition and reporting.
2. [FFprobe documentation](https://ffmpeg.org/ffprobe.html), opened 2026-10-03. Machine-readable stream, format and tag inspection is the basis of `formattruth`, `albumcontract` and `transcodeaudit`.
3. [aubio command-line documentation](https://aubio.org/manual/latest/cli.html), opened 2026-10-03. Existing programs extract onset, pitch, beats, note descriptors, and quiet/loud regions; generic onset, beat, silence and pitch commands were therefore not selected as gaps.
4. [Audacity editing FAQ](https://manual.audacityteam.org/man/faq_editing.html), opened 2026-10-03. Stereo zero crossings can occur at different points, supporting the broader principle that channel relationships need contextual inspection rather than a single endpoint metric.
5. [LoopAuditioneer README](https://github.com/GrandOrgue/LoopAuditioneer), opened 2026-10-03. It documents loop/cue evaluation, loop search, crossfading, metadata editing and batch preparation. `loopbudget` and `cueclock` complement rather than supersede it.
6. [FinalPass README](https://github.com/alexeymohr/FinalPass), opened 2026-10-03. It describes broader delivery QC including loudness, stem-sum null tests, channel integrity and downmix consistency. The tools here deliberately have smaller transparent scopes.
7. [Google audio-sync-kit README](https://github.com/google/audio-sync-kit), opened 2026-10-03. Reference/actual comparisons can report offsets and dropout intervals. `renderdelta` does not claim comparable automatic synchronization analysis.
8. [MDN decodeAudioData documentation](https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData), opened 2026-10-03. Browser decoding resamples to the AudioContext sample rate; explicit WAV parsing remains preferable for source-frame-accurate browser/CLI parity in the original ten tools.

## Engineering limits derived from the comparison

Use quarter-note BPM consistently and account for the time-signature denominator in musical arithmetic. Calculate each cue from its ideal absolute time before rounding to a sample; repeatedly adding a rounded beat length accumulates avoidable drift. Keep frame ranges end-exclusive and show both frame indices and seconds.

Analyze channels independently where summing could hide activity through cancellation. Correlation and phase values are evidence, not diagnoses of wiring faults or mono incompatibility. DC means describe offsets, not electrical fault diagnoses. Near-rail runs describe sampled amplitudes, not whether an upstream analog device clipped.

Preserve source frame counts for the original WAV analysis suite. Never silently resample a stem to make a contract pass. Difference WAVs require a declared offset, compatible rates/channel counts, and a defined overlap. Reports should distinguish unexamined regions from a clean comparison.

For shell-native tools, tolerate optional FFprobe fields and small FFmpeg-version differences. Keep locale-independent numeric parsing, deterministic batch ordering, explicit error outcomes and read-only source handling. `transcodeaudit` must never state that technical metadata proves a previous lossy transcode. `stereotruth` and `phasewatch` must never state that correlation alone proves an audio defect.
