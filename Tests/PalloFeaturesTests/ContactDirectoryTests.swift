import Testing
@testable import PalloCore
@testable import PalloFeatures

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

@Test func removingPersonAlsoRemovesTheirLinkRecord() throws {
    var directory = ContactDirectory()
    try directory.createPerson(id: "temporary", displayName: "Temporary")
    try directory.link(remoteIdentityID: "temporary-wa", to: "temporary")
    #expect(directory.links["temporary"] != nil)

    directory.removePerson(id: "temporary")
    #expect(directory.people["temporary"] == nil)
    #expect(directory.links["temporary"] == nil)
}
