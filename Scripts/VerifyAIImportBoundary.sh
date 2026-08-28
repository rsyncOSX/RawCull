#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
cd "$repository_root"

if ! command -v rg >/dev/null 2>&1; then
    echo "error: AI import boundary check requires ripgrep (rg)." >&2
    exit 1
fi

concrete_modules="
CoreAICLIPBackend
CoreAISAM3Backend
CoreAIEfficientSAMBackend
VisionFeaturePrintBackend
"

importing_files() {
    module=$1
    rg --files-with-matches --sort path --pcre2 --glob '*.swift' \
        "^[[:space:]]*(?:@(?:_implementationOnly|preconcurrency|testable)[[:space:]]+)*import[[:space:]]+(?:(?:class|enum|func|protocol|struct|typealias|var|let)[[:space:]]+)?${module}(?:[.]|[[:space:];]|$)" \
        RawCull 2>/dev/null || true
}

is_allowed_concrete_import() {
    module=$1
    file=$2

    case "$module:$file" in
        CoreAICLIPBackend:RawCull/Model/AIIntegration/RawCullAIIntegration.swift) return 0 ;;
        CoreAISAM3Backend:RawCull/Model/AIIntegration/RawCullAIIntegration.swift) return 0 ;;
        CoreAIEfficientSAMBackend:RawCull/Model/AIIntegration/RawCullAIIntegration.swift) return 0 ;;
        VisionFeaturePrintBackend:RawCull/Model/AIIntegration/RawCullAIIntegration.swift) return 0 ;;
        VisionFeaturePrintBackend:RawCull/Model/AIIntegration/RawCullVisionSimilarityService.swift) return 0 ;;
        *) return 1 ;;
    esac
}

violation_count=0

for module in $concrete_modules; do
    for file in $(importing_files "$module"); do
        if ! is_allowed_concrete_import "$module" "$file"; then
            echo "error: concrete backend import is outside the approved boundary: $file imports $module" >&2
            violation_count=$((violation_count + 1))
        fi
    done
done

contract_warning_count=0
for file in $(importing_files PhotoAIContracts); do
    case "$file" in
        RawCull/Model/AIIntegration/*|RawCull/Actors/*) ;;
        *)
            echo "warning: PhotoAIContracts remains outside the intelligence/persistence boundary: $file" >&2
            contract_warning_count=$((contract_warning_count + 1))
            ;;
    esac
done

if [ "$violation_count" -ne 0 ]; then
    echo "AI import boundary check failed with $violation_count concrete-backend violation(s)." >&2
    exit 1
fi

echo "AI import boundary check passed; $contract_warning_count non-blocking PhotoAIContracts leakage warning(s)."
