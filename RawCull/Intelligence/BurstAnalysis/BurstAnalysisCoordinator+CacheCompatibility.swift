import Foundation
import RawCullCore

extension BurstAnalysisCoordinator {
    nonisolated static func restoredReviewStates(
        snapshots: [BurstReviewStateSnapshot],
        groups: [BurstGroup],
        files: [FileItem],
        catalog: URL,
    ) -> [Int: BurstReviewState] {
        let savedStates = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.signature, $0.state) },
        )
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            let groupFiles = group.fileIDs.compactMap { filesByID[$0] }
            guard let signature = BurstGroupSignature(
                files: groupFiles,
                catalog: catalog,
            ),
                let state = savedStates[signature],
                state != .none
            else { return nil }
            return (group.id, state)
        })
    }

    nonisolated static func remap(
        _ snapshot: BurstAnalysisCacheSnapshot,
        to currentFiles: [FileItem],
    ) -> BurstAnalysisCacheSnapshot {
        let cachedFilesByID = Dictionary(
            uniqueKeysWithValues: snapshot.files.map { ($0.id, $0) },
        )
        let currentByPath = Dictionary(
            uniqueKeysWithValues: currentFiles.map { ($0.url.path, $0.id) },
        )
        let idMap = Dictionary(uniqueKeysWithValues: cachedFilesByID.compactMap { oldID, file in
            currentByPath[file.path].map { (oldID, $0) }
        })

        let groups = snapshot.groups.map { group in
            BurstGroup(
                id: group.id,
                fileIDs: group.fileIDs.map { idMap[$0] ?? $0 },
            )
        }

        return BurstAnalysisCacheSnapshot(
            schemaVersion: snapshot.schemaVersion,
            algorithmVersion: snapshot.algorithmVersion,
            catalogPath: snapshot.catalogPath,
            thumbnailMaxPixelSize: snapshot.thumbnailMaxPixelSize,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: snapshot.similaritySignature,
            files: currentFiles.map {
                BurstAnalysisCacheFile(
                    id: $0.id,
                    path: $0.url.path,
                    size: $0.size,
                    modificationDate: $0.dateModified,
                )
            },
            embeddings: Dictionary(uniqueKeysWithValues: snapshot.embeddings.compactMap { oldID, artifact in
                idMap[oldID].map { ($0, artifact) }
            }),
            sharpnessScores: Dictionary(
                uniqueKeysWithValues: snapshot.sharpnessScores.compactMap { oldID, score in
                    idMap[oldID].map { ($0, score) }
                },
            ),
            saliencyInfo: Dictionary(uniqueKeysWithValues: snapshot.saliencyInfo.compactMap { oldID, info in
                idMap[oldID].map { ($0, info) }
            }),
            groups: groups,
            boundaryEvidence: remappedEvidence(snapshot.boundaryEvidence, idMap: idMap),
            results: remappedResults(snapshot.results, idMap: idMap),
            reviewStateSnapshots: snapshot.reviewStateSnapshots,
            similarityArtifactSetDigest: snapshot.similarityArtifactSetDigest,
        )
    }

    private nonisolated static func remappedEvidence(
        _ evidence: [BurstBoundaryEvidence],
        idMap: [UUID: UUID],
    ) -> [BurstBoundaryEvidence] {
        evidence.map { item in
            BurstBoundaryEvidence(
                previousID: idMap[item.previousID] ?? item.previousID,
                currentID: idMap[item.currentID] ?? item.currentID,
                visualDistance: item.visualDistance,
                timeGapSeconds: item.timeGapSeconds,
                captureTimeUsedFallback: item.captureTimeUsedFallback,
                focalLengthDelta: item.focalLengthDelta,
                exposureAdjustmentEV: item.exposureAdjustmentEV,
                exposureChanged: item.exposureChanged,
                cameraChanged: item.cameraChanged,
                lensChanged: item.lensChanged,
                startsNewGroup: item.startsNewGroup,
                reasons: item.reasons,
            )
        }
    }

    private nonisolated static func remappedResults(
        _ results: [BurstAnalysisResult],
        idMap: [UUID: UUID],
    ) -> [BurstAnalysisResult] {
        results.map { result in
            BurstAnalysisResult(
                groupID: result.groupID,
                fileIDs: result.fileIDs.map { idMap[$0] ?? $0 },
                candidates: result.candidates.map { candidate in
                    BurstCandidateScore(
                        fileID: idMap[candidate.fileID] ?? candidate.fileID,
                        overallScore: candidate.overallScore,
                        sharpnessComponent: candidate.sharpnessComponent,
                        burstRelativeSharpnessComponent: candidate.burstRelativeSharpnessComponent,
                        focusPointComponent: candidate.focusPointComponent,
                        saliencyComponent: candidate.saliencyComponent,
                        metadataComponent: candidate.metadataComponent,
                        confidence: candidate.confidence,
                        reasons: candidate.reasons,
                        cautions: candidate.cautions,
                    )
                },
                recommendedFileID: result.recommendedFileID.map { idMap[$0] ?? $0 },
                secondBestFileID: result.secondBestFileID.map { idMap[$0] ?? $0 },
                confidence: result.confidence,
                reviewState: result.reviewState,
                isSafeForOneClickCulling: result.isSafeForOneClickCulling,
                reasons: result.reasons,
                cautions: result.cautions,
            )
        }
    }
}
