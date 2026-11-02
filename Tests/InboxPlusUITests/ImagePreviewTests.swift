import Foundation
import Testing
@testable import InboxPlusUI

@Test func imagePreviewFitsBothOrientationsWithoutUpscaling() {
    let viewport = CGSize(width: 800, height: 600)
    #expect(ImagePreview.fitScale(image: CGSize(width: 1600, height: 900), viewport: viewport) == 0.5)
    #expect(ImagePreview.fitScale(image: CGSize(width: 600, height: 1800), viewport: viewport) == 1.0 / 3)
    #expect(ImagePreview.fitScale(image: CGSize(width: 100, height: 100), viewport: viewport) == 1)
}

@Test func savingAnImagePreservesItsOriginalBytesAndCanReplaceAChosenFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.png")
    let destination = directory.appendingPathComponent("saved.png")
    // Save the original encoded data rather than rendering an NSImage into a new file.
    let original = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=")!
    try original.write(to: source)
    try Data("old file".utf8).write(to: destination)
    try ImagePreview.saveOriginal(from: source, to: destination)
    #expect(try Data(contentsOf: destination) == original)
    #expect(try Data(contentsOf: source) == original)
}
