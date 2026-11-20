nonisolated enum ReviewRunError: Error {
    case invalidSnapshot, sourceUnavailable, modelUnavailable, invalidDependency, invalidTransition, budgetExhausted
    case incompatible, corrupt, unsupportedVersion(Int), storageLimit, invalidEvidence
}
