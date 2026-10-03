# Research and tool selection

Research date: 2026-10-03 UTC. This is a practical workflow comparison, not proof that no similar program exists. Searches covered official FFmpeg and aubio documentation, Audacity's manual, and public project README files. General operations such as trimming, peak measurement, silence detection, correlation, and subtraction already exist. The proposed value is their focused combinations, explicit flags, machine-readable reports, modest dependencies, and matching local browser execution.

Exact-name searches found no audio results for the proposed names in the sampled search results. `LoopBudget` is already used by an unrelated AI coding budget service, so the command name does not imply exclusive branding or trademark clearance. An empty result cannot establish worldwide novelty.

## The selected ten

| Command | Narrow workflow and useful output | Existing overlap and differentiation |
| --- | --- | --- |
| `loopbudget` | Compare a WAV loop's boundary discontinuity and frame length against an explicit BPM, meter, and bar count; show sample rounding and duration error. | LoopAuditioneer evaluates and edits loops. FFmpeg loops and trims audio. This command combines seam evidence with a musical frame budget in one small report; it does not claim new loop analysis. |
| `tailbudget` | Locate last above-threshold activity and calculate how much quiet tail remains; optionally trim a copy while preserving a chosen pad. | FFmpeg silence detection/removal and SoX trimming cover the primitives. A keep-pad budget and explicit before/after frame accounting make the intended export decision clear. |
| `monoledger` | Report time-coded stereo windows with correlation and mono fold-down energy loss. | FFmpeg offers correlation and channel mixing; FinalPass checks channel integrity and downmix consistency. The focused ledger locates specific windows rather than replacing comprehensive delivery QC. |
| `gapcontext` | Report quiet-run candidates with active flanks, minimum duration, and surrounding context measurements. | aubioquiet and FFmpeg already detect quiet regions. Requiring active neighbors narrows candidate review; silence is not proof of a recording dropout. |
| `railruns` | Group near-full-scale samples into per-channel bursts and export their frame/time ledger. | FFmpeg astats reports peak-related statistics. This small tool emphasizes burst positions and consecutive-run lengths; it cannot establish the origin of clipping or restore missing peaks. |
| `dcjourney` | Calculate windowed channel means and the global mean in an offset timeline. | FFmpeg astats measures DC offset and dcshift changes it. The difference is the compact temporal journey rather than a new DC detector. |
| `gainbudget` | Calculate per-channel sample-peak headroom for requested gain and ceiling; optionally write a bounded-gain copy. | FFmpeg volume and statistics already support gain and peaks. This workflow explains the requested versus available gain before exporting. Sample-peak ceilings are not true-peak guarantees. |
| `stemcontract` | Validate a set of named WAV stems against explicit rate, channels, and frame-count requirements; report missing names and per-file mismatches; extra names are allowed. | FinalPass provides broader post-production delivery QC. This tool is a small contract validator for a particular handoff and makes no claim to BWF, Atmos, or loudness compliance. |
| `cueclock` | Generate a musical cue grid as integer sample positions and show timing-rounding drift for user-supplied tempo and meter. | aubio estimates beat positions from audio; LoopAuditioneer handles WAV cue metadata. This tool generates a deterministic arithmetic grid rather than detecting tempo or estimating beats. |
| `renderdelta` | Compare two compatible renders with explicit offset and output residual-energy windows plus an optional difference WAV. | Google audio-sync-kit compares reference/actual audio and reports synchronization/dropout evidence; FinalPass includes stem-sum null checks. This focused tool produces an offset-aware residual ledger without claiming automatic alignment or perceptual equivalence. |

These are deliberately modest tools. They use established formulas and do not require source separation, speech recognition, online services, or machine-learning model downloads. They should be described as original implementations of selected workflows, not ten previously nonexistent categories.

## Primary sources reviewed

1. [FFmpeg filter documentation](https://ffmpeg.org/ffmpeg-filters.html), opened 2026-10-03. Relevant documented primitives include `astats`, `silencedetect`, `silenceremove`, `atrim`, `apad`, `axcorrelate`, `pan`, `dcshift`, `volume`, and `aloop`. These support the overlap assessment; a composed FFmpeg pipeline can reproduce many individual operations.
2. [aubio command-line documentation](https://aubio.org/manual/latest/cli.html), opened 2026-10-03. Existing programs extract onset, pitch, beats, note descriptors, and quiet/loud regions; aubiocut segments audio. Consequently generic onset, beat, silence, and pitch tools were not selected as novel ideas.
3. [Audacity editing FAQ](https://manual.audacityteam.org/man/faq_editing.html), opened 2026-10-03. The manual explains that stereo zero crossings can occur at different points, leaving a click in one channel. This supports checking every channel at a loop seam; a small endpoint jump alone cannot guarantee a perceptually seamless loop.
4. [LoopAuditioneer README](https://github.com/GrandOrgue/LoopAuditioneer), opened 2026-10-03. It documents loop/cue evaluation, loop search, crossfading, metadata editing, and batch preparation. `loopbudget` and `cueclock` complement rather than supersede that software.
5. [FinalPass README](https://github.com/alexeymohr/FinalPass), opened 2026-10-03. It describes delivery QC including loudness, stem-sum null tests, channel integrity, and downmix consistency. `stemcontract`, `monoledger`, and `renderdelta` deliberately have a smaller scope.
6. [Google audio-sync-kit README](https://github.com/google/audio-sync-kit), opened 2026-10-03. Reference/actual comparisons can report offsets and dropout intervals. `renderdelta` avoids suggesting that simple residual subtraction offers that full synchronization analysis.
7. [MDN decodeAudioData documentation](https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData), opened 2026-10-03. Browser decoding resamples to the AudioContext sample rate. Explicit WAV parsing is therefore preferable for source-frame-accurate CLI/browser parity; Web Audio playback can be separate from measurements.

## Engineering limits derived from the comparison

Use quarter-note BPM consistently and account for the time-signature denominator in musical arithmetic. Calculate each cue from its ideal absolute time before rounding to a sample; repeatedly adding a rounded beat length accumulates avoidable drift. Keep frame ranges end-exclusive and show both frame indices and seconds.

Analyze channels independently where summing could hide activity through cancellation. A silent channel cannot provide meaningful normalized correlation. DC means describe offsets, not electrical fault diagnoses. Near-rail runs describe sampled amplitudes, not whether an upstream analog device clipped.

Preserve source frame counts for analysis. Reject unsupported WAV encodings explicitly. Never silently resample a stem to make a contract pass. Difference WAVs require a declared offset, compatible rates/channel counts, and a defined overlap. Reports should distinguish unexamined regions from a clean comparison.

Python and JavaScript are suitable independent implementations for these loops and arithmetic. Bash, batch, and PowerShell scripts can provide convenient launchers, but launchers depending on Python are not native language ports. Broader codec support can be added with an optional decoder later without changing the PCM analysis definitions.
