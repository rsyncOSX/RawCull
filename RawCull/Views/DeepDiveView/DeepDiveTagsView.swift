// DeepDiveTagsView.swift
// RawCull
//
// Created by Thomas Evensen on 25/02/2026.
//

// MARK: - Main View

import SwiftUI

struct DeepDiveTagsView: View {
    @Binding var showDetailsTagView: Bool
    @State private var viewModel = DeepDiveTagsViewModel()
    @State private var selectedTab: Tab = .properties
    @State private var searchText = ""
    @State private var selectedIndex = 0

    /// Pass a URL to load; for preview/demo purposes use an optional
    var url: URL?

    enum Tab: String, CaseIterable, Identifiable {
        case properties = "Properties"
        case xmp = "XMP Tags"
        var id: Self {
            self
        }
    }

    var body: some View {
        // Do NOT use NavigationStack here if this view is already inside one
        // (e.g. presented as a sheet or detail pane). Wrap only at the app root.
        // The toolbar crash comes from nested NavigationStacks + searchable
        // registering conflicting AppKit toolbar identifiers.
        VStack(spacing: 0) {
            // ── Custom inline toolbar replacement ──────────────────────────
            HStack(spacing: 12) {
                // Title block
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.fileName.isEmpty ? "Metadata Inspector" : viewModel.fileName)
                        .font(.headline)
                        .lineLimit(1)
                    if !viewModel.fileType.isEmpty {
                        Text(viewModel.fileType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Index picker (only when multiple indices exist)
                if viewModel.imageMetadata.count > 1 {
                    IndexPickerView(selectedIndex: $selectedIndex, count: viewModel.imageMetadata.count)
                }

                // Tab switcher — plain buttons avoid toolbar identifier issues
                TabToggleView(selectedTab: $selectedTab)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // ── Search field ───────────────────────────────────────────────
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)

                TextField("Filter tags…", text: $searchText)
                    .textFieldStyle(.plain)

                Button("Return", systemImage: "return") {
                    showDetailsTagView.toggle()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .labelStyle(.iconOnly)

                if !searchText.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") {
                        searchText = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .labelStyle(.iconOnly)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.background)

            Divider()

            // ── Content ────────────────────────────────────────────────────
            Group {
                if viewModel.isLoading {
                    LoadingView()
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                } else if viewModel.imageMetadata.isEmpty {
                    EmptyStateView()
                } else {
                    mainContent
                }
            }
        }
        .task {
            if let url {
                await viewModel.load(url: url)
            }
        }
    }

    private var mainContent: some View {
        let current = viewModel.imageMetadata[selectedIndex]
        return Group {
            switch selectedTab {
            case .properties:
                PropertiesTabView(entries: current.entries, searchText: searchText)

            case .xmp:
                XMPTabView(tags: current.xmpTags, searchText: searchText)
            }
        }
    }
}

// MARK: - Tab Toggle (avoids segmented Picker toolbar conflicts)

struct TabToggleView: View {
    @Binding var selectedTab: DeepDiveTagsView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DeepDiveTagsView.Tab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button(tab.rawValue) {
                    selectedTab = tab
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.clear)
                .contentShape(.rect)
            }
        }
        .background(.secondary.opacity(0.12))
        .clipShape(.rect(cornerRadius: 7))
    }
}

// MARK: - Index Picker

struct IndexPickerView: View {
    @Binding var selectedIndex: Int
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("Index:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Image Index", selection: $selectedIndex) {
                ForEach(0 ..< count, id: \.self) { i in
                    Text("\(i)").tag(i)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

// MARK: - Properties Tab

struct PropertiesTabView: View {
    let entries: [MetadataEntry]
    let searchText: String

    var filteredEntries: [MetadataEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter { entry in
            entry.key.localizedStandardContains(searchText) || entryContainsSearch(entry: entry)
        }
    }

    private func entryContainsSearch(entry: MetadataEntry) -> Bool {
        switch entry.value {
        case let .scalar(s): return s.localizedStandardContains(searchText)
        case let .array(arr): return arr.contains { $0.localizedStandardContains(searchText) }
        case let .group(_, children): return children.contains { entryContainsSearch(entry: $0) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(filteredEntries) { entry in
                    MetadataEntryView(entry: entry, depth: 0)
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Metadata Entry View

struct MetadataEntryView: View {
    let entry: MetadataEntry
    let depth: Int
    @State private var isExpanded = true

    private var indentPadding: CGFloat {
        CGFloat(depth) * 16
    }

    var body: some View {
        switch entry.value {
        case let .scalar(value):
            ScalarRowView(key: entry.key, value: value, depth: depth)

        case let .array(items):
            ArrayRowView(key: entry.key, items: items, depth: depth)

        case let .group(_, children):
            GroupRowView(
                key: entry.key,
                children: children,
                depth: depth,
                isExpanded: $isExpanded
            )
        }
    }
}

// MARK: - Scalar Row

struct ScalarRowView: View {
    let key: String
    let value: String
    let depth: Int

    private var indentPadding: CGFloat {
        CGFloat(depth) * 16
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 160, alignment: .leading)
            Spacer()
            Text(formattedValue)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .padding(.leading, indentPadding)
        .padding(.horizontal, 8)
        .background(depth % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
        .clipShape(.rect(cornerRadius: 4))
    }

    private var formattedValue: String {
        // Format known numeric keys nicely
        if key == "ExposureTime", let d = Double(value) {
            let formatted = 1 / d
            return "1/\(Int(formatted.rounded())) s"
        }
        return value
    }
}

// MARK: - Array Row

struct ArrayRowView: View {
    let key: String
    let items: [String]
    let depth: Int
    @State private var isExpanded = false

    private var indentPadding: CGFloat {
        CGFloat(depth) * 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                    Text(key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Array(\(items.count))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 4))
                }
                .padding(.vertical, 4)
                .padding(.leading, indentPadding)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items.enumerated(), id: \.offset) { index, item in
                        HStack {
                            Text("[\(index)]")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(minWidth: 30, alignment: .trailing)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .padding(.leading, indentPadding + 20)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(depth % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
        .clipShape(.rect(cornerRadius: 4))
    }
}

// MARK: - Group Row

struct GroupRowView: View {
    let key: String
    let children: [MetadataEntry]
    let depth: Int
    @Binding var isExpanded: Bool

    private var indentPadding: CGFloat {
        CGFloat(depth) * 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.caption)
                        .foregroundStyle(isExpanded ? .blue : .secondary)
                    Text(cleanGroupKey(key))
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(children.count) tags")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                .padding(.leading, indentPadding)
                .padding(.horizontal, 8)
                .background(Color.blue.opacity(isExpanded ? 0.07 : 0.03))
                .clipShape(.rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(children) { child in
                        MetadataEntryView(entry: child, depth: depth + 1)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 2)
    }

    private func cleanGroupKey(_ key: String) -> String {
        // Strip curly braces from group keys like "{Exif}", "{TIFF}" etc.
        key.replacing("{", with: "").replacing("}", with: "")
    }
}

// MARK: - XMP Tab

struct XMPTabView: View {
    let tags: [XMPTag]
    let searchText: String

    var filteredTags: [XMPTag] {
        guard !searchText.isEmpty else { return tags }
        return tags.filter {
            $0.path.localizedStandardContains(searchText) ||
                $0.value.localizedStandardContains(searchText)
        }
    }

    /// Group by namespace prefix
    var groupedTags: [(namespace: String, tags: [XMPTag])] {
        var groups: [String: [XMPTag]] = [:]
        for tag in filteredTags {
            let ns = tag.path.components(separatedBy: ":").first ?? "other"
            groups[ns, default: []].append(tag)
        }
        return groups.keys.sorted().map { ns in
            (namespace: ns, tags: groups[ns]!)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(groupedTags, id: \.namespace) { group in
                    XMPNamespaceGroupView(namespace: group.namespace, tags: group.tags)
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - XMP Namespace Group

struct XMPNamespaceGroupView: View {
    let namespace: String
    let tags: [XMPTag]
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(namespaceColor)
                        .frame(width: 4, height: 16)
                    Text(namespace.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(tags.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tags) { tag in
                        XMPTagRowView(tag: tag)
                        if tag.id != tags.last?.id {
                            Divider()
                                .padding(.leading, 8)
                        }
                    }
                }
                .background(.secondary.opacity(0.04))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.1), lineWidth: 1)
                )
            }
        }
    }

    private var namespaceColor: Color {
        switch namespace {
        case "exif": return .blue
        case "tiff": return .orange
        case "xmp", "xmpMM": return .purple
        case "aux": return .green
        case "dc": return .red
        case "exifEX": return .cyan
        case "photoshop": return .indigo
        default: return .gray
        }
    }
}

// MARK: - XMP Tag Row

struct XMPTagRowView: View {
    let tag: XMPTag

    var localName: String {
        tag.path.components(separatedBy: ":").last ?? tag.path
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(localName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, alignment: .leading)
            Spacer()
            Text(tag.value.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
    }
}

// MARK: - Summary Card

struct SummaryCardView: View {
    let metadata: ImageIndexMetadata

    /// Extract key EXIF values for quick summary
    private func scalar(_ key: String, in entries: [MetadataEntry]) -> String? {
        for entry in entries {
            if entry.key == key, case let .scalar(v) = entry.value { return v }
            if case let .group(_, children) = entry.value, let found = scalar(key, in: children) { return found }
        }
        return nil
    }

    var body: some View {
        let entries = metadata.entries

        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                if let make = scalar("Make", in: entries), let model = scalar("Model", in: entries) {
                    QuickInfoChip(icon: "camera.fill", label: "\(make) \(model)")
                }
                if let lens = scalar("LensModel", in: entries) {
                    QuickInfoChip(icon: "circle.dashed", label: lens)
                }
                if let exp = scalar("ExposureTime", in: entries), let d = Double(exp) {
                    let den = Int((1 / d).rounded())
                    QuickInfoChip(icon: "timer", label: "1/\(den)s")
                }
                if let fn = scalar("FNumber", in: entries) {
                    QuickInfoChip(icon: "camera.aperture", label: "f/\(fn)")
                }
                if let isos = entries.first(where: {
                    $0.key == "{Exif}"
                }),
                    case let .group(_, exifChildren) = isos.value,
                    let isoEntry = exifChildren.first(where: { $0.key == "ISOSpeedRatings" }),
                    case let .array(arr) = isoEntry.value,
                    let first = arr.first {
                    QuickInfoChip(icon: "bolt.fill", label: "ISO \(first)")
                }
                if let w = scalar("PixelWidth", in: entries), let h = scalar("PixelHeight", in: entries) {
                    QuickInfoChip(icon: "photo", label: "\(w) × \(h)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

struct QuickInfoChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.secondary.opacity(0.1))
        .clipShape(.rect(cornerRadius: 20))
    }
}

// MARK: - State Views

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading metadata…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.gearshape")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No metadata loaded")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
