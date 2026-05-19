import Foundation

struct BurstGroupingOutput: Equatable {
    let groups: [BurstGroup]
    let boundaryEvidence: [BurstBoundaryEvidence]
}

enum BurstGroupingEngine {
    nonisolated static func group(
        files: [FileItem],
        adjacentDistances: [String: Float],
        config: BurstGroupingConfig,
    ) -> BurstGroupingOutput {
        guard !files.isEmpty else {
            return BurstGroupingOutput(groups: [], boundaryEvidence: [])
        }

        var rawGroups: [[UUID]] = [[files[0].id]]
        var evidence: [BurstBoundaryEvidence] = []

        for index in files.indices.dropFirst() {
            let previous = files[index - 1]
            let current = files[index]
            let key = BurstPairKey.cacheKey(previousID: previous.id, currentID: current.id)
            let visualDistance = adjacentDistances[key]
            let timeGap = current.dateModified.timeIntervalSince(previous.dateModified)
            let focalDelta = focalLengthDelta(previous: previous, current: current)
            let cameraChanged = normalized(previous.exifData?.camera) != normalized(current.exifData?.camera)
            let lensChanged = normalized(previous.exifData?.lensModel) != normalized(current.exifData?.lensModel)
            let exposureChanged = exposureChanged(previous: previous, current: current)

            var startsNewGroup = false
            var reasons: [String] = []

            if let visualDistance {
                if visualDistance >= config.visualDistanceThreshold {
                    startsNewGroup = true
                    reasons.append("Visual distance changed")
                }
            } else {
                startsNewGroup = true
                reasons.append("Similarity evidence missing")
            }

            if abs(timeGap) > config.maxTimeGapSeconds {
                startsNewGroup = true
                reasons.append("Capture gap")
            }

            if config.requireSameCamera, cameraChanged {
                startsNewGroup = true
                reasons.append("Camera changed")
            }

            if config.requireSimilarFocalLength,
               let focalDelta,
               focalDelta > config.maxFocalLengthDeltaMM {
                startsNewGroup = true
                reasons.append("Focal length changed")
            }

            if exposureChanged {
                startsNewGroup = true
                reasons.append("Exposure changed")
            }

            evidence.append(BurstBoundaryEvidence(
                previousID: previous.id,
                currentID: current.id,
                visualDistance: visualDistance,
                timeGapSeconds: abs(timeGap),
                focalLengthDelta: focalDelta,
                exposureChanged: exposureChanged,
                cameraChanged: cameraChanged,
                lensChanged: lensChanged,
                startsNewGroup: startsNewGroup,
                reasons: reasons,
            ))

            if startsNewGroup {
                rawGroups.append([current.id])
            } else {
                rawGroups[rawGroups.index(before: rawGroups.endIndex)].append(current.id)
            }
        }

        let groups = rawGroups.enumerated().map { BurstGroup(id: $0.offset, fileIDs: $0.element) }
        return BurstGroupingOutput(groups: groups, boundaryEvidence: evidence)
    }

    private nonisolated static func exposureChanged(previous: FileItem, current: FileItem) -> Bool {
        let previousExif = previous.exifData
        let currentExif = current.exifData

        if let previousAperture = previousExif?.apertureValue,
           let currentAperture = currentExif?.apertureValue,
           abs(previousAperture - currentAperture) > 0.2 {
            return true
        }

        if let previousISO = previousExif?.isoValue,
           let currentISO = currentExif?.isoValue,
           previousISO != currentISO {
            return true
        }

        if let previousShutter = previousExif?.shutterSpeed,
           let currentShutter = currentExif?.shutterSpeed,
           previousShutter != currentShutter {
            return true
        }

        return false
    }

    private nonisolated static func focalLengthDelta(previous: FileItem, current: FileItem) -> Double? {
        guard let previousFocal = focalLengthMM(previous.exifData?.focalLength),
              let currentFocal = focalLengthMM(current.exifData?.focalLength)
        else { return nil }
        return abs(previousFocal - currentFocal)
    }

    private nonisolated static func focalLengthMM(_ value: String?) -> Double? {
        guard let value else { return nil }
        let digits = value.prefix { character in
            character.isNumber || character == "."
        }
        return Double(digits)
    }

    private nonisolated static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
