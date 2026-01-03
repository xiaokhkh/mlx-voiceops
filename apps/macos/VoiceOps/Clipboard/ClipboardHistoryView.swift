import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let onInject: (ClipboardItem) -> Void

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            VStack(spacing: 12) {
                searchBar
                Divider().opacity(0.4)
                listView
            }
            .padding(16)
        }
        .frame(width: 560, height: 420)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            Text(viewModel.query.isEmpty ? "Search clipboard" : viewModel.query)
                .foregroundColor(viewModel.query.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        )
    }

    private var listView: some View {
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
                            onDelete: { viewModel.deleteItem(item) }
                        )
                    }
                }
            }
        }
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
