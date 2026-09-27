# Sift Future Work

## Apple Intelligence

- Check `SystemLanguageModel.default.availability` before generation and distinguish unsupported devices, disabled Apple Intelligence, a model that is not ready, and unsupported locales.
- Treat extractive fallback results as upgradeable. Keep generated Apple Intelligence results authoritative, but allow a cached fallback to be replaced once the system model becomes available.
- Deduplicate concurrent generation for the same article and prompt version so one article cannot start multiple model requests.
- Replace the global generation Boolean with operation-aware state so overlapping article and briefing requests report progress correctly.
- Stop swallowing SwiftData save failures. Log them and surface a recoverable error when a generated result could not be persisted.
- Introduce `VersionedSchema` and `SchemaMigrationPlan` before adding more fields to intelligence models.
- Keep every generative request on-device. Do not add Private Cloud Compute or another remote model path; use extractive fallback when Apple Intelligence is unavailable.
- Add an explicit regenerate/upgrade action without making normal article opens regenerate an already saved Apple Intelligence result.

## Siri and App Intents

- Expose article title and feed title with `@Property` on `ArticleEntity` when they need to be searchable or filterable by the system.
- Make `ArticleEntityQuery.entities(for:)` query requested IDs directly instead of loading the complete article store and filtering in memory.
- Consider exposing the specific-article summary intent as an App Shortcut in addition to its Shortcuts action.
- Return user-visible App Intent errors with `CustomLocalizedStringResourceConvertible` or an appropriate `AppIntentError` instead of converting failures into successful dialog text.
- Review newer App Intents execution-mode APIs before release and migrate soft-deprecated declarations where deployment targets allow it.

## Translation and Speech

- Detect the article language and offer “Read in App Language” when it differs from the app language.
- Prefer Apple’s Translation framework for faithful full-article translation; use Foundation Models to summarize or rewrite the translated content for natural spoken delivery.
- Include the target locale in Foundation Models instructions and verify it with `SystemLanguageModel.supportsLocale(_:)`.
- Cache translations by article content hash, source language, target language, and translation version.
- Select the highest-quality installed `AVSpeechSynthesisVoice` matching the output language, preferring premium and then enhanced quality.
- Split spoken content into sentence or paragraph utterances and tune rate, pitch, and pauses rather than speaking the whole article as one flat utterance.
- Add a voice picker and clearly indicate when a premium/enhanced voice needs to be downloaded from system settings.
- Keep original and translated text separately so switching language never overwrites the publisher’s content.
