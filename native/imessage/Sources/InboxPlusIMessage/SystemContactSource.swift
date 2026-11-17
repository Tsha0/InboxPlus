import Contacts
import Foundation

/// Reads names and photos from the Mac's Contacts, asking for access the first time iMessage loads.
///
/// Access is optional: without it every handle is still shown, as a formatted number or address.
public struct SystemContactSource: IMessageContactSource {
    public init() {}

    public func contactBook() async -> IMessageContactBook {
        IMessageContactBook((try? await readContacts()) ?? [])
    }

    public func recipientContacts() async -> LocalRecipientSnapshot {
        do {
            guard let contacts = try await readContacts() else { return .accessUnavailable }
            return .available(Self.recipients(from: contacts))
        } catch {
            return .failed
        }
    }

    static func recipients(from contacts: [IMessageContactBook.Contact]) -> [LocalRecipient] {
        let recipients = contacts.flatMap { contact in
            (contact.phoneNumbers + contact.emailAddresses).compactMap { address -> LocalRecipient? in
                guard let normalized = try? IMessageGateway.normalizeRecipient(address) else { return nil }
                return LocalRecipient(name: contact.name, address: normalized)
            }
        }
        var seen: Set<String> = []
        return recipients.filter { seen.insert($0.id).inserted }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
                || ($0.name == $1.name && $0.address < $1.address)
        }
    }

    /// A saved photo sized for a list row, or empty data when the contact has none.
    public func thumbnailImageData(forContactID id: String) async throws -> Data {
        guard let store = await authorizedStore() else { throw CNError(.authorizationDenied) }
        let contact = try store.unifiedContact(
            withIdentifier: id, keysToFetch: [CNContactThumbnailImageDataKey as CNKeyDescriptor]
        )
        return contact.thumbnailImageData ?? Data()
    }

    private func authorizedStore() async -> CNContactStore? {
        // macOS terminates a process that touches Contacts without a usage description, and a bare
        // `swift run` build has no Info.plist to carry one.
        guard Bundle.main.object(forInfoDictionaryKey: "NSContactsUsageDescription") != nil else {
            return nil
        }
        let store = CNContactStore()
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
        }
        return CNContactStore.authorizationStatus(for: .contacts) == .authorized ? store : nil
    }

    private func readContacts() async throws -> [IMessageContactBook.Contact]? {
        guard let store = await authorizedStore() else { return nil }

        let request = CNContactFetchRequest(keysToFetch: [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
        ])
        var contacts: [IMessageContactBook.Contact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
            guard !name.isEmpty else { return }
            contacts.append(IMessageContactBook.Contact(
                name: name,
                shortName: contact.givenName.isEmpty ? nil : contact.givenName,
                phoneNumbers: contact.phoneNumbers.map(\.value.stringValue),
                emailAddresses: contact.emailAddresses.map { $0.value as String },
                photoID: contact.imageDataAvailable ? contact.identifier : nil
            ))
        }
        return contacts
    }
}
