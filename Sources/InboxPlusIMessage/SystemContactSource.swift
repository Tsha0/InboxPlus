import Contacts
import Foundation

/// Reads names from the Mac's Contacts, asking for access the first time iMessage loads.
///
/// Access is optional: without it every handle is still shown, as a formatted number or address.
public struct SystemContactSource: IMessageContactSource {
    public init() {}

    public func contactBook() async -> IMessageContactBook {
        // macOS terminates a process that touches Contacts without a usage description, and a bare
        // `swift run` build has no Info.plist to carry one.
        guard Bundle.main.object(forInfoDictionaryKey: "NSContactsUsageDescription") != nil else {
            return IMessageContactBook()
        }
        let store = CNContactStore()
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
        }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return IMessageContactBook()
        }

        let request = CNContactFetchRequest(keysToFetch: [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ])
        var contacts: [IMessageContactBook.Contact] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
            guard !name.isEmpty else { return }
            contacts.append(IMessageContactBook.Contact(
                name: name,
                shortName: contact.givenName.isEmpty ? nil : contact.givenName,
                phoneNumbers: contact.phoneNumbers.map(\.value.stringValue),
                emailAddresses: contact.emailAddresses.map { $0.value as String }
            ))
        }
        return IMessageContactBook(contacts)
    }
}
