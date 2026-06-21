import SwiftUI

struct FileRecordDetailView: View {
    let record: FileRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader
                    .padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 12) {
                    SavedFilesSectionHeader(title: "File Details")

                    DetailRow(icon: "tag.fill", label: "Date Tagged", value: record.dateTagged ?? "—")
                    Divider()
                    DetailRow(icon: "arrow.right.doc.on.clipboard", label: "Date Copied", value: record.dateCopied ?? "—")
                    Divider()

                    HStack(alignment: .center) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Rating")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        if let rating = record.rating {
                            StarRatingView(rating: rating, compact: false)
                            Text("(\(rating)/5)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 4)
                        } else {
                            Text("—")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor)),
                )

                if record.sharpnessScore != nil || record.saliencySubject != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        SavedFilesSectionHeader(title: "Sharpness Analysis")

                        if let score = record.sharpnessScore {
                            DetailRow(
                                icon: "viewfinder.circle",
                                label: "Sharpness",
                                value: String(format: "%.2f", score),
                            )
                        }

                        if record.sharpnessScore != nil, record.saliencySubject != nil {
                            Divider()
                        }

                        if let subject = record.saliencySubject {
                            HStack(alignment: .center) {
                                Image(systemName: "eye")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text("Subject")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                Text(subject)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.cyan.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.cyan)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor)),
                    )
                    .padding(.top, 12)
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var detailHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }

            Text(record.fileName ?? "Unnamed File")
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(2)

            Spacer()
        }
    }
}
