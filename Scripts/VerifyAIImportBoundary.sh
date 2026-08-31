#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
cd "$repository_root"

if ! command -v rg >/dev/null 2>&1; then
    echo "error: AI import boundary check requires ripgrep (rg)." >&2
    exit 1
fi

restricted_modules="
CoreAICLIPBackend
CoreAISAM3Backend
CoreAIEfficientSAMBackend
VisionFeaturePrintBackend
PhotoAIContracts
PhotoAIStorage
PhotoAIWorkflows
"

importing_files() {
    module=$1
    rg --files-with-matches --sort path --pcre2 --glob '*.swift' \
        "^[[:space:]]*(?:@(?:_implementationOnly|preconcurrency|testable)[[:space:]]+)*import[[:space:]]+(?:(?:class|enum|func|protocol|struct|typealias|var|let)[[:space:]]+)?${module}(?:[.]|[[:space:];]|$)" \
        RawCull 2>/dev/null || true
}

is_allowed_import() {
    module=$1
    file=$2

    case "$module:$file" in
        CoreAICLIPBackend:RawCull/Intelligence/Composition/RawCullAIIntegration.swift) return 0 ;;
        CoreAISAM3Backend:RawCull/Intelligence/Composition/RawCullAIIntegration.swift) return 0 ;;
        CoreAIEfficientSAMBackend:RawCull/Intelligence/Composition/RawCullAIIntegration.swift) return 0 ;;
        VisionFeaturePrintBackend:RawCull/Intelligence/Composition/RawCullAIIntegration.swift) return 0 ;;
        VisionFeaturePrintBackend:RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift) return 0 ;;
        PhotoAIStorage:RawCull/Intelligence/Composition/RawCullAIIntegration.swift) return 0 ;;
        PhotoAIStorage:RawCull/Intelligence/Persistence/PerFileAnalysisArtifactStore.swift) return 0 ;;
        PhotoAIWorkflows:RawCull/Intelligence/Composition/RawCullAIIntegration.swift) return 0 ;;
        PhotoAIWorkflows:RawCull/Intelligence/DeepReview/DeepAIReviewFeature.swift) return 0 ;;
        PhotoAIWorkflows:RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/BurstAnalysis/BurstAnalysisCoordinator.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/Composition/RawCullAIIntegration.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/Composition/RawCullIntelligenceRuntime.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/Contracts/RawCullAIModels.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/DeepReview/DeepAIReviewFeature.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/ModelManagement/RawCullAIModelResourceManager.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/Persistence/BurstAnalysisCache.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/Persistence/PerFileAnalysisArtifactStore.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/Presentation/SemanticSearchUIPresentation.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/SemanticSearch/RawCullSemanticSearchService.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/Similarity/RawCullSimilarityFeature.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/Similarity/RawCullVisionSimilarityService.swift) return 0 ;;
        PhotoAIContracts:RawCull/Intelligence/Similarity/SimilarityScoringModel.swift) return 0 ;;
        *) return 1 ;;
    esac
}

violation_count=0

for module in $restricted_modules; do
    for file in $(importing_files "$module"); do
        if ! is_allowed_import "$module" "$file"; then
            echo "error: restricted AI import is outside the exact allowlist: $file imports $module" >&2
            violation_count=$((violation_count + 1))
        fi
    done
done

if rg --quiet '^[[:space:]]*convenience init[[:space:]]*\(' \
    RawCull/Model/ViewModels/RawCullViewModel.swift; then
    echo "error: RawCullViewModel compatibility initializer was reintroduced." >&2
    violation_count=$((violation_count + 1))
fi

if rg --quiet '^[[:space:]]*let[[:space:]]+similarityModel[[:space:]]*:' \
    RawCull/Intelligence/Composition/RawCullIntelligenceRuntime.swift; then
    echo "error: the runtime must not expose the low-level similarity model." >&2
    violation_count=$((violation_count + 1))
fi

if rg --quiet '\.similarityModel\b' RawCull/Views; then
    echo "error: a SwiftUI view bypasses the focused similarity feature." >&2
    rg --line-number '\.similarityModel\b' RawCull/Views >&2
    violation_count=$((violation_count + 1))
fi

obsolete_view_model_surface='^[[:space:]]*(?:func|var)[[:space:]]+(?:searchSemantically|setSemanticSearchShowsAllResults|adjustSemanticSearchSelection|clearSemanticSearch|cancelSemanticSearch|indexSimilarity|setSimilarityService|setSemanticSearchCapability|startDeepAIReview|cancelDeepAIReview|deepAIReviewRequest|isDeepAIReviewUnavailable)\b'
if rg --pcre2 --quiet "$obsolete_view_model_surface" RawCull/Model/ViewModels; then
    echo "error: an obsolete intelligence forwarding member was reintroduced on RawCullViewModel." >&2
    rg --pcre2 --line-number "$obsolete_view_model_surface" RawCull/Model/ViewModels >&2
    violation_count=$((violation_count + 1))
fi

if [ "$violation_count" -ne 0 ]; then
    echo "AI dependency boundary check failed with $violation_count violation(s)." >&2
    exit 1
fi

echo "AI dependency boundary check passed; restricted imports and removed compatibility surfaces match the exact policy."
