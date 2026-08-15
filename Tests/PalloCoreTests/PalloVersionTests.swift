import Foundation
import Testing
@testable import PalloCore

@Test func versionsCompareNumericallyNotAsText() {
    // The reason this exists: "0.10.0" sorts before "0.9.0" as a string, so an updater comparing
    // text would offer a downgrade as an upgrade.
    #expect(PalloVersion.compare("0.10.0", "0.9.0") == .orderedDescending)
    #expect(PalloVersion.compare("1.0.0", "1.0.0") == .orderedSame)
    #expect(PalloVersion.compare("1.2.3", "1.2.4") == .orderedAscending)
}

@Test func aShorterVersionIsTreatedAsZeroPadded() {
    #expect(PalloVersion.compare("1.2", "1.2.0") == .orderedSame)
    #expect(PalloVersion.compare("1.2", "1.2.1") == .orderedAscending)
    #expect(PalloVersion.compare("2", "1.9.9") == .orderedDescending)
}

@Test func onlyAHigherVersionCountsAsAnUpgrade() {
    #expect(PalloVersion.isUpgrade(from: "0.5.0", to: "0.6.0"))
    #expect(!PalloVersion.isUpgrade(from: "0.6.0", to: "0.5.0"))
    #expect(!PalloVersion.isUpgrade(from: "0.5.0", to: "0.5.0"))
}

@Test func theShippedVersionIsParseable() {
    #expect(PalloVersion.compare(PalloVersion.current, "0.0.0") == .orderedDescending)
}
