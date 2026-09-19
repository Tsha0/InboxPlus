import Foundation
import Testing
@testable import MimoCore

@Test func versionsCompareNumericallyNotAsText() {
    // The reason this exists: "0.10.0" sorts before "0.9.0" as a string, so an updater comparing
    // text would offer a downgrade as an upgrade.
    #expect(MimoVersion.compare("0.10.0", "0.9.0") == .orderedDescending)
    #expect(MimoVersion.compare("1.0.0", "1.0.0") == .orderedSame)
    #expect(MimoVersion.compare("1.2.3", "1.2.4") == .orderedAscending)
}

@Test func aShorterVersionIsTreatedAsZeroPadded() {
    #expect(MimoVersion.compare("1.2", "1.2.0") == .orderedSame)
    #expect(MimoVersion.compare("1.2", "1.2.1") == .orderedAscending)
    #expect(MimoVersion.compare("2", "1.9.9") == .orderedDescending)
}

@Test func onlyAHigherVersionCountsAsAnUpgrade() {
    #expect(MimoVersion.isUpgrade(from: "0.5.0", to: "0.6.0"))
    #expect(!MimoVersion.isUpgrade(from: "0.6.0", to: "0.5.0"))
    #expect(!MimoVersion.isUpgrade(from: "0.5.0", to: "0.5.0"))
}

@Test func theShippedVersionIsParseable() {
    #expect(MimoVersion.compare(MimoVersion.current, "0.0.0") == .orderedDescending)
}
