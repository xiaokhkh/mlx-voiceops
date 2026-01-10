import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let onInject: (ClipboardItem) -> Void
    let onHoverImage: (ClipboardItem?) -> Void

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            VStack(spacing: 12) {
                header
                searchBar
                Divider().opacity(0.4)
                listView
                footer
            }
            .padding(16)
        }
        .frame(width: 560, height: 420)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard History")
                    .font(.headline)
                Text("Type to search, Enter to paste")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(viewModel.items.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            Text(viewModel.query.isEmpty ? "Search clipboard" : viewModel.query)
                .foregroundColor(viewModel.query.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            if !viewModel.query.isEmpty {
                Button(action: { viewModel.clearQuery() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(viewModel.query.isEmpty ? Color.clear : Color.accentColor.opacity(0.4))
        )
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.items.isEmpty {
                        Text("No clipboard history yet")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            ClipboardItemRowView(
                                item: item,
                                isSelected: index == viewModel.selectedIndex,
                                metaText: viewModel.metaText(for: item),
                                onSelect: { viewModel.selectIndex(index) },
                                onCopy: { viewModel.copyItem(item) },
                                onPin: { viewModel.togglePinned(item) },
                                onInject: { onInject(item) },
                                onDelete: { viewModel.deleteItem(item) },
                                onHoverImage: { hovered in
                                    onHoverImage(hovered)
                                }
                            )
                            .id(item.id)
                        }
                    }
                }
            }
            .onChange(of: viewModel.selectedIndex) { _ in
                guard viewModel.items.indices.contains(viewModel.selectedIndex) else { return }
                let item = viewModel.items[viewModel.selectedIndex]
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(item.id, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Copy") {
                if let item = selectedItem {
                    viewModel.copyItem(item)
                }
            }
            .buttonStyle(.bordered)
            .disabled(selectedItem == nil)

            Button("Paste") {
                if let item = selectedItem {
                    onInject(item)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedItem == nil)

            Button("Pin") {
                if let item = selectedItem {
                    viewModel.togglePinned(item)
                }
            }
            .buttonStyle(.bordered)
            .disabled(selectedItem == nil)

            Button("Delete") {
                if let item = selectedItem {
                    viewModel.deleteItem(item)
                }
            }
            .buttonStyle(.bordered)
            .disabled(selectedItem == nil)

            Spacer()

            Text("Cmd+C Copy | Enter Paste | Cmd+Delete")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var selectedItem: ClipboardItem? {
        guard viewModel.items.indices.contains(viewModel.selectedIndex) else { return nil }
        return viewModel.items[viewModel.selectedIndex]
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
