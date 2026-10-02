import InboxPlusCore

public enum ContactDirectoryError: Error, Equatable {
    case duplicatePerson
    case missingPerson
    case identityAlreadyLinked
    case invalidInitialState
}

public struct ContactDirectory: Sendable {
    public private(set) var people: [String: InboxPlusPerson]
    public private(set) var links: [String: PersonLink]
    private var personByIdentityID: [String: String]

    public init() {
        people = [:]
        links = [:]
        personByIdentityID = [:]
    }

    public init(people: [String: InboxPlusPerson], links: [String: PersonLink]) throws {
        var personByIdentityID: [String: String] = [:]

        for (personID, person) in people {
            guard person.id == personID else { throw ContactDirectoryError.invalidInitialState }
        }

        for (personID, link) in links {
            guard people[personID] != nil, link.personID == personID else {
                throw ContactDirectoryError.invalidInitialState
            }
            for remoteIdentityID in link.remoteIdentityIDs {
                guard personByIdentityID[remoteIdentityID] == nil else {
                    throw ContactDirectoryError.invalidInitialState
                }
                personByIdentityID[remoteIdentityID] = personID
            }
        }

        self.people = people
        self.links = links
        self.personByIdentityID = personByIdentityID
    }

    public mutating func createPerson(id: String, displayName: String) throws {
        guard people[id] == nil else { throw ContactDirectoryError.duplicatePerson }
        people[id] = InboxPlusPerson(id: id, displayName: displayName)
    }

    public mutating func link(remoteIdentityID: String, to personID: String) throws {
        guard people[personID] != nil else { throw ContactDirectoryError.missingPerson }
        guard self.personID(linkedTo: remoteIdentityID) == nil else {
            throw ContactDirectoryError.identityAlreadyLinked
        }
        var link = links[personID] ?? PersonLink(personID: personID, remoteIdentityIDs: [])
        link.remoteIdentityIDs.insert(remoteIdentityID)
        links[personID] = link
        personByIdentityID[remoteIdentityID] = personID
    }

    public mutating func unlink(remoteIdentityID: String, from personID: String) throws {
        guard var link = links[personID] else { throw ContactDirectoryError.missingPerson }
        link.remoteIdentityIDs.remove(remoteIdentityID)
        if personByIdentityID[remoteIdentityID] == personID {
            personByIdentityID[remoteIdentityID] = nil
        }
        links[personID] = link
    }

    mutating func removePerson(id: String) {
        for identityID in links[id]?.remoteIdentityIDs ?? [] {
            personByIdentityID[identityID] = nil
        }
        people[id] = nil
        links[id] = nil
    }

    public func personID(linkedTo remoteIdentityID: String) -> String? {
        personByIdentityID[remoteIdentityID]
    }
}
