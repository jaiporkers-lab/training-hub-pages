# Optional on-device AI

This source feature adds comparison highlights. The published 0.9.0 download remains unchanged until a tested release is made.

For a separate test app, run `zsh scripts/build-ai-preview.sh`. It creates `../GarHub-AI-Preview.zip` with bundle ID `local.traininghub.ai.preview`, a fresh `GarHubAIPreview` application-support library, separate preferences and a separate Garmin Keychain service. It does not replace the stable installation or copy its recordings or key. Import your own files explicitly when you want to try it.

## Use

1. Open **Settings → On-device AI** and turn on **Enable on-device AI features**. It is off by default.
2. Open **Compare**, choose two activities and select elapsed time or recorded timer.
3. Select **Choose on-device highlights**. Use **Stop** to cancel. Turning the settings switch off cancels work and clears the result.

The model selects up to three verified facts. GarHub computes all values and supplies every displayed sentence. The full comparison and its limitations remain available. It supports single-sport and matched multisport legs; the model sees at most the first six leg rows, with a clear limit for longer recordings.

## Local boundary

The only inference implementation constructs `LanguageModelSession(model: SystemLanguageModel.default, tools: [])`. Apple's `SystemLanguageModel` is explicitly on-device; the broader Foundation Models framework also supports cloud models, so importing the framework alone would not establish locality. This implementation has no cloud model, provider switching, remote inference, ChatGPT integration or network tool. It needs no AI API key or per-inference payment. Apple's system may need to download model assets before local use. [Apple model documentation](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [Apple framework introduction](https://developer.apple.com/videos/play/wwdc2025/360/).

Only app-authored duration/distance values and opaque evidence keys enter the prompt. Activity names, notes, routes, raw recordings, sensor streams, health values, file paths and credentials are excluded. Internal source IDs bind a result to its evidence but are omitted from the model input. No transcripts, result cache or diagnostic payloads are saved or uploaded. There is no prewarming or background generation. Existing Garmin sync and optional Apple Maps are separate network functions.

Runtime schemas limit output to permitted fact IDs. The app independently rejects unknown, duplicate, empty and oversized selections. Mandatory caveats are displayed outside model-selected content. Missing values never become zero; recorded timer never falls back to elapsed in a comparison. Routes and conditions are unknown, so less recorded time is not a claim of improved performance. AI does not assess health, recovery, readiness, injury risk or prescribe training. Default Apple guardrails remain enabled; errors and refusals retain the verified comparison facts.

## Compatibility and operation

- App baseline: macOS 14+. The framework is weak linked and only used inside macOS 26+ availability checks.
- Inference: eligible Apple Intelligence Mac, supported app locale, Apple Intelligence available and model assets ready. Runtime availability is checked again for each request. [Apple requirements](https://support.apple.com/en-au/121115).
- Unsupported system, language, downloading model, disabled Apple Intelligence or generation error: ordinary app features and verified comparison facts remain available. There is no cloud fallback or automatic settings change.
- A request snapshots the evidence. Selection/time-basis/evidence changes and leaving the panel cancel it. Late/cancelled results cannot render against different evidence. One backend operation is allowed at a time, including while cancellation completes.
- A 20-second deadline ends the visible request immediately and cancels the backend. Off clears the result immediately. Results are not persisted; the on/off preference is per Mac and excluded from library backups.
- Context is bounded to eight facts, a small schema and 128 output tokens. Oversized or failed requests fall back. No whole-library chat history is sent.

## Build and verification

Build using Xcode 26+ for the model adapter, or compile it out explicitly with:

```sh
swift build --build-system native -Xswiftc -DGARHUB_NO_ON_DEVICE_AI
swift test --build-system native
```

Tests use synthetic FIT fixtures and isolated preferences. They cover missing/nonfinite values, repeated legs, output rejection, default-off behaviour, no generation when unavailable, cancellation, an uncooperative late backend, no overlapping calls and deadline fallback. They do not require Apple Intelligence or an external model.

Before a stable release, validate a fully offline run after model download; Settings/Compare UI; unsupported/disabled/downloading/language states; clean launch on macOS 14/15 and Intel; and cold/warm memory/latency on an 8 GB Mac. Re-run model quality checks after OS/model updates. The prototype's process-level network denial is narrower than a whole-Mac offline test.

### Validation on 15 November 2026

- Full suite: 115 tests executed, 3 optional private-recording tests skipped, 0 failures. The five request-control tests also passed after the API spelling compatibility change; the additional preview storage-identity test passed.
- Release preview: built for Apple silicon, locally signed and verified, macOS 14 minimum with weak FoundationModels linkage. The explicit compiled-out adapter built without FoundationModels symbols.
- The actual adapter selected verified synthetic comparison facts with direct network access denied to the test process. The model service is a separate macOS process; this is not a full offline audit.
- Actual packaged Settings UI: switch initially off, on reports an available local model, then off again. No private library or saved key was used. New view components were rendered and inspected with synthetic comparison values.
- Historical macOS/Intel launches, the full unavailable/download/language matrix and whole-Mac offline profiling remain release gates. The preview does not replace the stable app or stable website download.

## Follow-on work

Comparison highlights are the first increment. Natural-language library filters, workout summaries, weekly training/recovery summaries and bounded questions remain proposed work. They must reuse deterministic analysis and constrained read-only operations with separate evaluation; this switch does not enable an unrestricted coach or chat interface.
