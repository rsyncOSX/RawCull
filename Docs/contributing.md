# Contributor notes

## Error handling: when `try?` is fine

`try?` is fine for:

- best-effort cleanup (`removeItem`, `close()`) and `Task.sleep`
- decoding optional fields with a default, for format compatibility (`SettingsViewModel`, `BurstAnalysisCache` init)
- validation used as a yes/no check (`(try? admit(...)) != nil`)
- tolerant parsing of model output where a fallback path exists

Everything else uses `do`/`catch` with a `Logger` line, or rethrows.

Never turn a failure into a constant value. `(try? encoder.encode(x)) ?? Data()` makes every
input that fails to encode share one value, for example one cache key for every photo. The
SwiftLint rule `try_optional_empty_data_fallback` in `.swiftlint.yml` rejects that pattern.

Background: [code-quality-followups-plan.md, Finding 5](code-quality-followups-plan.md#finding-5-fix-the-try-uses-that-hide-failures).
