/// Runs a fixed number of operations at a time and preserves input order.
func boundedConcurrentMap<Input: Sendable, Output: Sendable>(
    _ inputs: [Input],
    limit: Int,
    operation: @escaping @Sendable (Input) async throws -> Output
) async throws -> [Output] {
    try Task.checkCancellation()
    return try await withThrowingTaskGroup(of: (Int, Output).self) { group in
        var next = 0
        var results: [Int: Output] = [:]
        for _ in 0..<min(max(1, limit), inputs.count) {
            let index = next
            next += 1
            group.addTask { (index, try await operation(inputs[index])) }
        }
        while let (index, result) = try await group.next() {
            try Task.checkCancellation()
            results[index] = result
            if next < inputs.count {
                let index = next
                next += 1
                group.addTask { (index, try await operation(inputs[index])) }
            }
        }
        return inputs.indices.compactMap { results[$0] }
    }
}
