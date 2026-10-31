import Foundation

/// Where the names behind Messages handles come from.
///
/// A seam so tests can supply names without reading anyone's real Contacts.
public protocol IMessageContactSource: Sendable {
    func contactBook() async -> IMessageContactBook
}

/// Turns the phone numbers and email addresses Messages stores into the names the user knows.
///
/// A handle nobody is saved under still gets a readable title: a North American number is grouped
/// the way Messages shows it, and anything else is shown as stored.
public struct IMessageContactBook: IMessageContactSource {
    public struct Contact: Equatable, Sendable {
        public let name: String
        /// What a group title uses, where several full names would not fit.
        public let shortName: String
        public let phoneNumbers: [String]
        public let emailAddresses: [String]

        public init(
            name: String,
            shortName: String? = nil,
            phoneNumbers: [String] = [],
            emailAddresses: [String] = []
        ) {
            self.name = name
            self.shortName = shortName ?? name
            self.phoneNumbers = phoneNumbers
            self.emailAddresses = emailAddresses
        }
    }

    private var byPhoneDigits: [String: Contact] = [:]
    private var byEmail: [String: Contact] = [:]

    public init(_ contacts: [Contact] = []) {
        for contact in contacts {
            for number in contact.phoneNumbers {
                for key in Self.keys(forContactNumber: number) where byPhoneDigits[key] == nil {
                    byPhoneDigits[key] = contact
                }
            }
            for address in contact.emailAddresses where byEmail[address.lowercased()] == nil {
                byEmail[address.lowercased()] = contact
            }
        }
    }

    public func contactBook() async -> IMessageContactBook { self }

    public func name(forHandle handle: String) -> String {
        contact(forHandle: handle)?.name ?? Self.formatted(handle)
    }

    /// Titles a group nobody has named after the people in it, such as "Alex, Sam +3".
    public func groupTitle(forHandles handles: [String]) -> String? {
        let names = handles.map { contact(forHandle: $0)?.shortName ?? Self.formatted($0) }
        guard !names.isEmpty else { return nil }
        guard names.count > 3 else { return names.joined(separator: ", ") }
        return names.prefix(2).joined(separator: ", ") + " +\(names.count - 2)"
    }

    func contact(forHandle handle: String) -> Contact? {
        if handle.contains("@") { return byEmail[handle.lowercased()] }
        let digits = Self.digits(handle)
        guard !digits.isEmpty else { return nil }
        if let exact = byPhoneDigits[digits] { return exact }
        // Messages stores a number with its country code, but people often save it without one.
        // Dropping no more than a country code keeps a local number saved without its area code
        // from matching someone in another area.
        for dropped in 1...3 where digits.count - dropped >= 7 {
            if let contact = byPhoneDigits[String(digits.dropFirst(dropped))] { return contact }
        }
        return nil
    }

    /// The digit strings a saved number is looked up by. A national number's trunk `0`, an
    /// international `00` prefix and a `(0)` never appear in the form Messages stores.
    static func keys(forContactNumber number: String) -> [String] {
        let digits = Self.digits(number.replacingOccurrences(of: "(0)", with: ""))
        if digits.hasPrefix("00") { return [digits, String(digits.dropFirst(2))] }
        if digits.hasPrefix("0") { return [digits, String(digits.dropFirst())] }
        return digits.isEmpty ? [] : [digits]
    }

    static func formatted(_ handle: String) -> String {
        let digits = Self.digits(handle)
        guard handle == "+" + digits, digits.count == 11, digits.hasPrefix("1") else { return handle }
        let area = digits.dropFirst().prefix(3)
        let exchange = digits.dropFirst(4).prefix(3)
        return "+1 (\(area)) \(exchange)-\(digits.suffix(4))"
    }

    private static func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }
}
