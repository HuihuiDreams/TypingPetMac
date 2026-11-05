import SwiftUI

struct CommunityGalleryView: View {
    var onSelect: (String) -> Void
    @State private var packs: [CommunityPackSummary] = []
    @State private var nextPage: Int? = 1
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(L("Community public packs")).font(.title2.weight(.semibold))
                    Spacer()
                    Button(L("Refresh")) { load(reset: true) }.disabled(busy)
                }
                Text(L("Explore packs shared publicly by the community. Preview any version before importing."))
                    .font(.callout).foregroundStyle(.secondary)
                if packs.isEmpty && !busy { Text(L("No community packs yet.")).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                    ForEach(packs) { pack in
                        Button { onSelect(pack.code) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                AsyncImage(url: LocalShareAPI.communityCover(code: pack.code, revision: pack.version)) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: { Image(systemName: "photo").foregroundStyle(.tertiary) }
                                    .frame(maxWidth: .infinity).frame(height: 116)
                                Text(pack.name).font(.headline).lineLimit(2).frame(height: 36, alignment: .top)
                                Text("v\(pack.version) · " + L("Images: %1$@", String(pack.presetCount)))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: pack.creatorMessage).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .top)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                if busy { ProgressView().controlSize(.small) }
                if !error.isEmpty { Text(error).font(.callout).foregroundStyle(.red) }
                if nextPage != nil && !packs.isEmpty { Button(L("Load more")) { load(reset: false) }.disabled(busy) }
            }.padding(24)
        }.onAppear { if packs.isEmpty { load(reset: true) } }
    }
    private func load(reset: Bool) {
        guard !busy else { return }; busy = true; error = ""
        let page = reset ? 1 : nextPage ?? 1
        Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await LocalShareAPI.community(page: page)
                if reset { packs = result.packs }
                else { packs.append(contentsOf: result.packs.filter { value in !packs.contains { $0.id == value.id } }) }
                nextPage = result.nextPage
            } catch { self.error = error.localizedDescription }
        }
    }
}
