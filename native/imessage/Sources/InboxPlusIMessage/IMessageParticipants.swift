import Foundation

extension IMessageStore {
    /// The handles of everyone else in a chat, which is what an unnamed group is titled from.
    public func participants(inChat chatRowID: Int64) throws -> [String] {
        // A person has a handle row per service, so iMessage and SMS for one number fold into one.
        let sql = """
        SELECT handle.id
        FROM chat_handle_join
        JOIN handle ON handle.ROWID = chat_handle_join.handle_id
        WHERE chat_handle_join.chat_id = \(chatRowID)
        GROUP BY handle.id
        ORDER BY MIN(handle.ROWID)
        """
        return try rows(sql) { Self.string($0, 0) ?? "" }
    }
}
