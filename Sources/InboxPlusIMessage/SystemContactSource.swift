import Contacts
import Foundation
import InboxPlusCore

/// Reads names from the Mac's Contacts, asking for access the first time iMessage loads.
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

    private func readContacts() async throws -> [IMessageContactBook.Contact]? {
        // macOS terminates a process that touches Contacts without a usage description, and a bare
        // `swift run` build has no Info.plist to carry one.
        guard Bundle.main.object(forInfoDictionaryKey: "NSContactsUsageDescription") != nil else {
            return nil
        }
        let store = CNContactStore()
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
        }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return nil
        }

        let request = CNContactFetchRequest(keysToFetch: [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ])
        var contacts: [IMessageContactBook.Contact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
            guard !name.isEmpty else { return }
            contacts.append(IMessageContactBook.Contact(
                name: name,
                shortName: contact.givenName.isEmpty ? nil : contact.givenName,
                phoneNumbers: contact.phoneNumbers.map(\.value.stringValue),
                emailAddresses: contact.emailAddresses.map { $0.value as String }
            ))
        }
        return contacts
    }
}
