import Foundation

/// Represents the final unit of data stored in your Vector DB
struct DocumentChunk: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let embedding: [Float]
    let metadata: [String: String] // Useful for tracing back to source PDF
}
