import Foundation

import StrataCore

// MARK: - Names

func normalizesMessyDesignNames() {
    expect(NameNormalizer.tokens(for: "Atlas Logo final final (Recovered) 2.ai") == ["atlas", "logo"])
    expect(NameNormalizer.tokens(for: "atlas_logo_FINAL_v2.ai") == ["atlas", "logo"])
    expect(NameNormalizer.tokens(for: "atlas-logo copy.pdf") == ["atlas", "logo"])
    expect(NameNormalizer.tokens(for: "AtlasLogo_v03.png") == ["atlas", "logo"])
    expect(NameNormalizer.tokens(for: "Nomad poster (Récupéré).psd") == ["nomad", "poster"])
    expect(NameNormalizer.key(for: "logo atlas.ai") == NameNormalizer.key(for: "Atlas_Logo_final.ai"))
}

func genericNamesNeverFormProjects() {
    expect(NameNormalizer.key(for: "Untitled-1.ai") == nil)
    expect(NameNormalizer.key(for: "Screenshot 2026-10-17 at 10.22.33.png") == nil)
    expect(NameNormalizer.key(for: "IMG_4821.jpg") == nil)
    expect(NameNormalizer.key(for: "logo_final_v2.ai") == nil)
}

func similarityNeedsASharedSpecificWord() {
    expect(NameNormalizer.similarity(["nike", "logo"], ["adidas", "logo"]) == 0)
    expect(NameNormalizer.similarity(["nike", "logo"], ["nike", "logo"]) == 1)
}

// MARK: - XMP

let illustratorXMP = """
<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF><rdf:Description rdf:about=""
  xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/" xmlns:stRef="http://ns.adobe.com/xap/1.0/sType/ResourceRef#"
  xmlns:xmp="http://ns.adobe.com/xap/1.0/"
  xmpMM:DocumentID="xmp.did:AAAA1111-2222" xmpMM:InstanceID="xmp.iid:BBBB"
  xmpMM:OriginalDocumentID="uuid:ORIG-0001-XYZ" xmp:CreatorTool="Adobe Illustrator 29.0">
  <xmpMM:DerivedFrom rdf:parseType="Resource">
    <stRef:instanceID>xmp.iid:PREV</stRef:instanceID>
    <stRef:documentID>xmp.did:PREVDOC-123</stRef:documentID>
    <stRef:originalDocumentID>uuid:ORIG-0001-XYZ</stRef:originalDocumentID>
  </xmpMM:DerivedFrom>
  <xmpMM:Pantry><rdf:Bag><rdf:li rdf:parseType="Resource">
    <xmpMM:DocumentID>xmp.did:PLACED-IMAGE-999</xmpMM:DocumentID>
  </rdf:li></rdf:Bag></xmpMM:Pantry>
</rdf:Description></rdf:RDF></x:xmpmeta>
"""

func readsAdobeIdentifiers() throws {
    let info = try require(XMPReader.parse(xml: illustratorXMP))
    expect(info.documentID == "xmp.did:aaaa1111-2222")
    expect(info.originalDocumentID == "uuid:orig-0001-xyz")
    expect(info.derivedFromIDs.contains("xmp.did:prevdoc-123"))
    expect(info.creatorTool == "Adobe Illustrator 29.0")
}

func ignoresPlacedFileIDs() throws {
    let xml = """
    <x:xmpmeta><rdf:Description><xmpMM:Pantry><rdf:li><xmpMM:DocumentID>xmp.did:PLACED-IMAGE-999</xmpMM:DocumentID></rdf:li></xmpMM:Pantry>
    <xmpMM:DocumentID>xmp.did:REAL-DOC-0001</xmpMM:DocumentID></rdf:Description></x:xmpmeta>
    """
    expect(XMPReader.parse(xml: xml)?.documentID == "xmp.did:real-doc-0001")
}

func findsPacketInsideBinaryData() throws {
    var data = Data(repeating: 0x00, count: 5000)
    data.append(Data("%PDF-1.6 junk".utf8))
    data.append(Data(illustratorXMP.utf8))
    data.append(Data(repeating: 0xFF, count: 5000))
    expect(XMPReader.parse(data: data)?.documentID == "xmp.did:aaaa1111-2222")
}

func rejectsPlaceholderIDs() {
    expect(XMPReader.normalizeID("xmp.did:00000000-0000-0000") == nil)
    expect(XMPReader.normalizeID("") == nil)
}

// MARK: - Grouping

func file(_ name: String, daysAgo: Double, doc: String? = nil, original: String? = nil,
          derived: [String] = [], folder: String = "/Users/me/Desktop", size: Int64 = 1000) -> CreativeFile {
    let ext = (name as NSString).pathExtension
    let xmp = (doc ?? original) == nil && derived.isEmpty ? nil
        : XMPInfo(documentID: doc, originalDocumentID: original, derivedFromIDs: derived)
    let date = Date(timeIntervalSince1970: 1_790_000_000 - daysAgo * 86400)
    return CreativeFile(path: "\(folder)/\(name)", kind: FileKind.from(extension: ext)!, size: size,
                        created: date, modified: date, xmp: xmp)
}

func groupsRenamedRecoveredAndExportedFilesIntoOneProject() throws {
    let files = [
        file("atlas-logo-sketch.ai", daysAgo: 200, doc: "did:atlas-1", original: "orig:atlas"),
        file("brand mark v2.ai", daysAgo: 60, doc: "did:other", original: "orig:atlas"),           // Save As to start a new job
        file("Untitled-3 (Recovered).ai", daysAgo: 180, doc: "did:atlas-2", original: "orig:atlas"), // crash recovery
        file("atlas_logo_final.ai", daysAgo: 100, doc: "did:atlas-3", original: "orig:atlas", folder: "/Users/me/Downloads"),
        file("atlas_logo_final.pdf", daysAgo: 99, folder: "/Users/me/Downloads"),                    // export, matched by name
        file("export-01.png", daysAgo: 98, derived: ["did:atlas-3"]),                               // export, matched by DerivedFrom
        file("nomad poster.psd", daysAgo: 50),
        file("Nomad_Poster_FINAL.psd", daysAgo: 40),
        file("Untitled-1.ai", daysAgo: 30),
        file("Untitled-2.ai", daysAgo: 20),
    ]
    let result = Grouper.group(files)
    expect(result.projects.count == 2)

    let atlas = try require(result.projects.first { $0.files.count == 5 })
    expect(atlas.name == "Atlas Logo")
    expect(atlas.first.file.name == "atlas-logo-sketch.ai")
    expect(atlas.latest.file.name == "atlas_logo_final.ai")
    expect(atlas.versions.count == 3)
    expect(atlas.hasRecovered)
    let final = try require(atlas.versions.last)
    expect(Set(atlas.exports(of: final).map(\.file.name)) == ["atlas_logo_final.pdf", "export-01.png"])

    let nomad = try require(result.projects.first { $0.name == "Nomad Poster" })
    expect(nomad.files.count == 2)
    expect(result.loose.map(\.name).sorted() == ["Untitled-1.ai", "Untitled-2.ai", "brand mark v2.ai"])
}

func templatesDoNotMergeUnrelatedClients() {
    // A stock template reused for many clients shares one OriginalDocumentID.
    let clients = ["nike", "adidas", "puma", "reebok", "fila", "asics", "mizuno", "umbro", "kappa"]
    let files = clients.enumerated().map { i, c in
        file("\(c) flyer.ai", daysAgo: Double(i * 30), doc: "did:\(c)", original: "orig:stock-template")
    }
    let result = Grouper.group(files)
    expect(result.projects.isEmpty)
    expect(result.loose.count == clients.count)
}

func differentProjectsOfSameClientStaySeparate() {
    let files = [
        file("nike logo.ai", daysAgo: 100), file("nike logo v2.ai", daysAgo: 90),
        file("nike poster.psd", daysAgo: 80), file("nike poster final.psd", daysAgo: 70),
        file("nike logo poster.ai", daysAgo: 60),
    ]
    let result = Grouper.group(files)
    let names = Set(result.projects.map(\.name))
    expect(names.contains("Nike Logo"))
    expect(names.contains("Nike Poster"))
}

func differentNamesAreDifferentProjects() {
    // Exported from one Photoshop document, but different artwork: not versions of each other.
    let files = [
        file("Cup Blue.png", daysAgo: 2, doc: "did:cup-mockup"),
        file("Cup Sky Blue.png", daysAgo: 1, doc: "did:cup-mockup"),
        file("atlas.ai", daysAgo: 10), file("atlas logo.ai", daysAgo: 5),
    ]
    let result = Grouper.group(files)
    expect(result.projects.isEmpty)
    expect(result.loose.count == 4)
}

func versionMarkersStillGroup() {
    let names = ["Cup Blue.png", "Cup Blue v2.png", "cup_blue_FINAL.png", "Cup Blue (Recovered).png", "Cup Blue copy.png", "Cup Blue (1).png"]
    let result = Grouper.group(names.enumerated().map { file($1, daysAgo: Double(10 - $0)) })
    expect(result.projects.count == 1)
    expect(result.projects.first?.files.count == names.count)
}

func flagsExactDuplicates() throws {
    let files = [
        file("riad promo.mp4", daysAgo: 10, size: 5000),
        file("riad promo (1).mp4", daysAgo: 9, folder: "/Users/me/Downloads", size: 5000),
    ]
    let result = Grouper.group(files, hasher: { _ in "same-hash" })
    let p = try require(result.projects.first)
    expect(p.duplicateCount == 1)
    expect(p.files[1].duplicateOf == p.files[0].file.path)
}

// MARK: - Scanner on real files

func scannerReadsRealFilesAndCaches() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("strata-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let padding = Data(repeating: 0x41, count: 4096)
    var ai = Data("%PDF-1.6\n".utf8); ai.append(Data(illustratorXMP.utf8)); ai.append(padding)
    try ai.write(to: dir.appendingPathComponent("client brand.ai"))
    try ai.write(to: dir.appendingPathComponent("totally different name (Recovered).ai"))
    try padding.write(to: dir.appendingPathComponent("notes.txt"))
    try Data(count: 100).write(to: dir.appendingPathComponent("tiny.png")) // below minimum size

    let cacheURL = dir.appendingPathComponent("cache.json")
    let scanner = Scanner(cache: MetadataCache(fileURL: cacheURL))
    let first = scanner.scan(roots: [dir])
    expect(first.files.count == 2)
    expect(first.xmpReads == 2)
    expect(first.files.allSatisfy { $0.xmp?.documentID == "xmp.did:aaaa1111-2222" })

    let again = Scanner(cache: MetadataCache(fileURL: cacheURL)).scan(roots: [dir])
    expect(again.xmpReads == 0)

    let result = Grouper.group(again.files)
    try require(result.projects.count == 1)
    expect(result.projects[0].files.allSatisfy { $0.reason == .sameDocument || $0.reason == .origin })
}

func repeatedNamesInProductFoldersStaySeparate() throws {
    let root = "/Users/me/Downloads"
    let products = ["01_MarketMorning", "02_FirstSwim", "03_TheCornerCafe", "04_FigsAndHoney"]
    var files = products.map { file("01_THUMBNAIL_sideboard.jpg", daysAgo: 5, folder: "\(root)/Shop/\($0)/2_Photos") }
    // The same product copied to an upload folder should still match its twin.
    files.append(file("01_THUMBNAIL_sideboard.jpg", daysAgo: 1, folder: "\(root)/TO_UPLOAD/Kitchen/06-FigsAndHoney/2_Photos"))
    let result = Grouper.group(files, roots: [root])
    try require(result.projects.count == 1)
    expect(result.projects[0].files.allSatisfy { $0.file.path.contains("FigsAndHoney") })
}

func printSizesAreOneArtwork() {
    let names = ["SolaraStudio_FigsHoney_11x14.pdf", "SolaraStudio_FigsHoney_ISO.pdf", "SolaraStudio_FigsHoney_4x5.pdf", "SolaraStudio_FigsHoney_A4.pdf"]
    let result = Grouper.group(names.map { file($0, daysAgo: 3) })
    expect(result.projects.count == 1)
    expect(result.projects.first?.name == "Solara Studio Figs Honey")
}

func saveAsToStartANewJobIsNotTheSameProject() {
    // Same client, new job started from last month's file: shares the Adobe origin but not the work.
    let files = [
        file("Norvia Machines.ai", daysAgo: 400, doc: "did:m", original: "orig:norvia"),
        file("Norvia calendar.ai", daysAgo: 380, doc: "did:c", original: "orig:norvia", derived: ["did:m"]),
        file("Habillage NORVIA.ai", daysAgo: 180, doc: "did:h", original: "orig:norvia", derived: ["did:c"]),
        file("Norvia calendar final.ai", daysAgo: 370, doc: "did:c2", original: "orig:norvia", derived: ["did:c"]),
    ]
    let result = Grouper.group(files)
    expect(result.projects.count == 1)
    expect(result.projects.first?.name == "Norvia Calendar")
    expect(result.loose.count == 2)
}

func manualCorrectionsWin() throws {
    let files = [
        file("atlas logo.ai", daysAgo: 30), file("atlas logo v2.ai", daysAgo: 20),
        file("random sketch.ai", daysAgo: 10),
    ]
    var o = Overrides()
    o.links = [[files[2].path, files[0].path]]          // "this sketch belongs to Atlas"
    o.projectNames = [files[0].path: "Atlas Brand Mark"]
    var result = Grouper.group(files, overrides: o)
    try require(result.projects.count == 1)
    expect(result.projects[0].files.count == 3)
    expect(result.projects[0].name == "Atlas Brand Mark")
    expect(result.projects[0].files.first { $0.file.name == "random sketch.ai" }?.reason == .manual)

    o = Overrides()
    o.detached = [files[1].path]                          // "v2 is not part of this"
    result = Grouper.group(files, overrides: o)
    expect(result.projects.isEmpty)
    expect(result.loose.count == 3)
}

func clientCorrectionsWin() throws {
    let root = "/Users/me/Documents"
    let files = [
        file("Velora Menu.ai", daysAgo: 30, folder: root), file("Velora Logo.ai", daysAgo: 20, folder: root),
        file("Kiosk top.ai", daysAgo: 10, folder: root + "/DAB KIOSK"), file("Kiosk side.ai", daysAgo: 9, folder: root + "/DAB KIOSK"),
    ]
    let grouping = Grouper.group(files, roots: [root])
    var o = Overrides()
    o.clientLinks = [[files[2].path, files[0].path]]
    o.clientNames = [files[0].path: "Velora Coffee Co"]
    var catalog = Collector.collect(grouping, roots: [root], overrides: o)
    try require(catalog.collections.count == 1)
    expect(catalog.collections[0].name == "Velora Coffee Co")
    expect(catalog.collections[0].fileCount == 4)

    o.hiddenClients = [files[1].path]
    catalog = Collector.collect(grouping, roots: [root], overrides: o)
    expect(catalog.collections.isEmpty && catalog.hidden.count == 1)
}

func readsFontsFromXMP() {
    let xml = """
    <x:xmpmeta><rdf:Description xmpMM:DocumentID="xmp.did:font-doc-1234">
    <xmpTPg:Fonts><rdf:Bag><rdf:li rdf:parseType="Resource"><stFnt:fontName>Inter-Bold</stFnt:fontName>
    <stFnt:fontFamily>Inter</stFnt:fontFamily></rdf:li><rdf:li rdf:parseType="Resource">
    <stFnt:fontFamily>Playfair Display</stFnt:fontFamily></rdf:li></rdf:Bag></xmpTPg:Fonts>
    </rdf:Description></x:xmpmeta>
    """
    expect(XMPReader.parse(xml: xml)?.fonts == ["Inter", "Playfair Display"])
}
