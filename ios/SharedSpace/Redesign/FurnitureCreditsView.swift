import SwiftUI

/// Where the catalogue's 3D models and product data come from, and their licenses.
struct FurnitureCreditsView: View {
    @Environment(\.dismiss) private var dismiss

    static let aboURL = URL(string: "https://amazon-berkeley-objects.s3.amazonaws.com/index.html")!
    static let ccByURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!

    private var abo: [CatalogPiece] { Catalogue.pieces.filter { $0.credit?.source == "Amazon Berkeley Objects" } }
    private var blenderKit: [CatalogPiece] { Catalogue.pieces.filter { $0.credit?.source == "BlenderKit" } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Amazon Berkeley Objects")
                        Text("Furniture 3D models and product data: Amazon Berkeley Objects, Amazon.com, CC BY 4.0. Models resized and converted to USDZ.")
                        Link("Amazon Berkeley Objects", destination: Self.aboURL).frame(minHeight: Size.tapTarget)
                        Link("CC BY 4.0 license", destination: Self.ccByURL).frame(minHeight: Size.tapTarget)
                        ForEach(abo) { piece in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(piece.name).textRole(.bodyStrong)
                                Text([piece.brand, piece.credit?.sourceURL?.lastPathComponent].compactMap { $0 }.joined(separator: " · "))
                                    .textRole(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("BlenderKit")
                        Text("These models are from BlenderKit, released under CC0 1.0 (public domain). Resized, simplified and converted to USDZ.")
                        ForEach(blenderKit) { piece in
                            if let credit = piece.credit {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(credit.sourceName) by \(credit.author)").textRole(.bodyStrong)
                                    HStack(spacing: Space.m) {
                                        if let url = credit.sourceURL { Link("On BlenderKit", destination: url) }
                                        if let url = credit.licenseURL { Link(credit.license, destination: url) }
                                    }
                                    .font(.detail)
                                    .frame(minHeight: Size.tapTarget)
                                }
                            }
                        }
                    }
                    Text("Sizes are each product’s real dimensions. Prices and store links aren’t shown.")
                        .textRole(.hint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation("Furniture credits")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
