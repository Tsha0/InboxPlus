import Testing
@testable import InboxPlusCore
@testable import InboxPlusFeatures

@Test func identitiesRemainUnlinkedUntilExplicitAction() throws {
    let directory = ContactDirectory()
    #expect(directory.personID(linkedTo: "maya-wa") == nil)
}

@Test func explicitLinkAndUnlinkDoNotDeleteThePerson() throws {
    var directory = ContactDirectory()
    try directory.createPerson(id: "maya", displayName: "Maya")
    try directory.link(remoteIdentityID: "maya-wa", to: "maya")
    #expect(directory.personID(linkedTo: "maya-wa") == "maya")

    try directory.unlink(remoteIdentityID: "maya-wa", from: "maya")
    #expect(directory.personID(linkedTo: "maya-wa") == nil)
    #expect(directory.people["maya"]?.displayName == "Maya")
}

@Test func oneRemoteIdentityCannotBelongToTwoPeople() throws {
    var directory = ContactDirectory()
    try directory.createPerson(id: "maya", displayName: "Maya")
    try directory.createPerson(id: "other", displayName: "Other")
    try directory.link(remoteIdentityID: "maya-wa", to: "maya")

    #expect(throws: ContactDirectoryError.identityAlreadyLinked) {
        try directory.link(remoteIdentityID: "maya-wa", to: "other")
    }
}

@Test func initialDirectoryRejectsDuplicateRemoteIdentityAssignment() throws {
    #expect(throws: ContactDirectoryError.invalidInitialState) {
        try ContactDirectory(
            people: [
                "maya": InboxPlusPerson(id: "maya", displayName: "Maya"),
                "other": InboxPlusPerson(id: "other", displayName: "Other"),
            ],
            links: [
                "maya": PersonLink(personID: "maya", remoteIdentityIDs: ["maya-wa"]),
                "other": PersonLink(personID: "other", remoteIdentityIDs: ["maya-wa"]),
            ]
        )
    }
}

@Test func initialDirectoryRejectsLinkRecordWithMismatchedPersonID() throws {
    #expect(throws: ContactDirectoryError.invalidInitialState) {
        try ContactDirectory(
            people: ["maya": InboxPlusPerson(id: "maya", displayName: "Maya")],
            links: ["maya": PersonLink(personID: "other", remoteIdentityIDs: ["maya-wa"])]
        )
    }
}

@Test func initialDirectoryRejectsPersonDictionaryKeyAndIDMismatch() {
    #expect(throws: ContactDirectoryError.invalidInitialState) {
        try ContactDirectory(
            people: ["dictionary-key": InboxPlusPerson(id: "embedded-id", displayName: "Maya")],
            links: [:]
        )
    }
}

@Test func initialDirectoryRejectsLinkWhoseOwnerIsMissing() {
    #expect(throws: ContactDirectoryError.invalidInitialState) {
        try ContactDirectory(
            people: ["maya": InboxPlusPerson(id: "maya", displayName: "Maya")],
            links: [
                "missing": PersonLink(personID: "missing", remoteIdentityIDs: ["missing-wa"]),
            ]
        )
    }
}

@Test func removingPersonAlsoRemovesTheirLinkRecord() throws {
    var directory = ContactDirectory()
    try directory.createPerson(id: "temporary", displayName: "Temporary")
    try directory.link(remoteIdentityID: "temporary-wa", to: "temporary")
    #expect(directory.links["temporary"] != nil)

    directory.removePerson(id: "temporary")
    #expect(directory.people["temporary"] == nil)
    #expect(directory.links["temporary"] == nil)
}

@Test func initializedIdentityIndexStaysConsistentAcrossUnlinkAndPersonRemoval() throws {
    var directory = try ContactDirectory(
        people: ["maya": InboxPlusPerson(id: "maya", displayName: "Maya")],
        links: ["maya": PersonLink(personID: "maya", remoteIdentityIDs: ["wa", "ig"])]
    )
    #expect(directory.personID(linkedTo: "wa") == "maya")
    try directory.unlink(remoteIdentityID: "wa", from: "maya")
    #expect(directory.personID(linkedTo: "wa") == nil)
    #expect(directory.personID(linkedTo: "ig") == "maya")
    directory.removePerson(id: "maya")
    #expect(directory.personID(linkedTo: "ig") == nil)
    try directory.createPerson(id: "other", displayName: "Other")
    try directory.link(remoteIdentityID: "ig", to: "other")
    #expect(directory.personID(linkedTo: "ig") == "other")
}
