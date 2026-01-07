import Foundation

actor RAGEngine {
    
    // MARK: - Properties
    private let embeddingEngine: EmbeddingEngine
    private var database: [DocumentChunk] = []
    
    // MARK: - Configuration
    private let chunkSize: Int = 400
    private let overlap: Int = 100
    
    init(embeddingEngine: EmbeddingEngine) {
        self.embeddingEngine = embeddingEngine
    }
        
    /// Processes a full page of text, chunks it, embeds it, and stores it.
    func add(text: String, metadata: [String: String] = [:]) async throws {
        // 1. CLEAN the text first (Remove headers/footers)
        let cleanedText = cleanText(text)
        
        // 2. Split
        let textChunks = recursiveSplit(text: cleanedText)
        
        for chunkText in textChunks {
            // FILTER: Skip chunks that are too short (less than 20 chars)
            if chunkText.count < 20 { continue }
            do {
                // Generate vector
                let vector = try await embeddingEngine.embed(text: chunkText)
                
                // Store in our "Database"
                let document = DocumentChunk(
                    text: chunkText,
                    embedding: vector,
                    metadata: [:]
                )
                database.append(document)
                
                print("\n ✅ Indexed chunk: \(chunkText)... \n")
            } catch {
                print("⚠️ Failed to embed chunk: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Retrieval (Search)
    
    /// Finds the most relevant chunks for a user query.
    func search(query: String, limit: Int = 3) async throws -> [DocumentChunk] {
        // 1. Embed the query
        let queryVector = try await embeddingEngine.embed(text: query)
        
        // 2. Compare against database (Cosine Similarity)
        // We calculate score for every chunk and sort them.
        let scoredDocs = database.map { doc -> (DocumentChunk, Float) in
            let score = cosineSimilarity(a: queryVector, b: doc.embedding)
            return (doc, score)
        }
        
        // 3. Sort by highest score (Desc) and take top 'limit'
        let sortedDocs = scoredDocs.sorted { $0.1 > $1.1 }
        for chunks in sortedDocs.enumerated() {
            print("\n\nSorted chunks with index: \(chunks.offset)\n Score: \(chunks.element.1) \nText: \(chunks.element.0.text)")
        }
        
        return sortedDocs.prefix(limit).map { $0.0 }
    }
    
    // MARK: - Helpers
    
    // MARK: - Improved Splitting Logic

    /// Smart Recursive Splitter with Overlap
    /// 1. Breaks text by separators (Paragraphs > Sentences > Words)
    /// 2. Merges parts until 'chunkSize' is reached
    /// 3. Retains the last few parts as overlap for the next chunk
    private func recursiveSplit(text: String, separators: [String] = ["\n\n", "\n", ". ", " ", ""]) -> [String] {
        var finalChunks: [String] = []
        let currentSeparator = separators.first ?? ""
        let nextSeparators = Array(separators.dropFirst())
        
        // 1. Initial Split
        // If separator is empty (char split), we map characters to strings
        let parts = currentSeparator.isEmpty
        ? text.map { String($0) }
        : text.components(separatedBy: currentSeparator)
        
        // 2. Buffer to build the current chunk
        var currentChunkParts: [String] = []
        var currentChunkLength = 0
        
        for part in parts {
            let partLen = part.count
            
            // Calculate length if we were to add this part
            // (current length + separator length + new part length)
            let separatorLen = currentChunkParts.isEmpty ? 0 : currentSeparator.count
            let potentialLength = currentChunkLength + separatorLen + partLen
            
            if potentialLength > chunkSize {
                
                // A. Finalize the current chunk (if it has content)
                if !currentChunkParts.isEmpty {
                    let chunk = currentChunkParts.joined(separator: currentSeparator)
                    finalChunks.append(chunk)
                    
                    // --- OVERLAP LOGIC ---
                    // Remove items from the front until we are below the overlap limit.
                    // This keeps the "tail" of the previous chunk to be the "head" of the new one.
                    while currentChunkLength > overlap && currentChunkParts.count > 1 {
                        currentChunkParts.removeFirst()
                        // Recalculate length accurately
                        currentChunkLength = currentChunkParts.joined(separator: currentSeparator).count
                    }
                    // If even the last item is bigger than overlap, we keep it anyway
                    // to maintain semantic continuity (don't break a sentence in half).
                }
                
                // B. Handle the new part
                if partLen > chunkSize {
                    // If the part *itself* is massive (bigger than chunk limit), we recurse.
                    if !nextSeparators.isEmpty {
                        let subChunks = recursiveSplit(text: part, separators: nextSeparators)
                        finalChunks.append(contentsOf: subChunks)
                        
                        // After a recursive split, the context stream is broken.
                        // We reset the buffer to avoid mixing distinct contexts cleanly.
                        currentChunkParts = []
                        currentChunkLength = 0
                    } else {
                        // Edge case: No separators left, but text is still too big.
                        // Force a hard cut by characters.
                        finalChunks.append(String(part.prefix(chunkSize)))
                    }
                } else {
                    // The new part fits into the new chunk (which now contains the overlap)
                    currentChunkParts.append(part)
                    // Update length
                    currentChunkLength = currentChunkParts.joined(separator: currentSeparator).count
                }
                
            } else {
                // It fits in the current chunk, just add it.
                currentChunkParts.append(part)
                currentChunkLength += (currentChunkParts.count > 1 ? separatorLen : 0) + partLen
            }
        }
        
        // 3. Final flush of any remaining buffer
        if !currentChunkParts.isEmpty {
            let chunk = currentChunkParts.joined(separator: currentSeparator)
            // Prevent duplicates if the last logic step already added this exactly
            if finalChunks.last != chunk {
                finalChunks.append(chunk)
            }
        }
        
        return finalChunks
    }
    
    /// Cosine Similarity Math
    /// safe Cosine Similarity
    /// This automatically "normalizes" the vectors by dividing by their length.
    /// Bulletproof Cosine Similarity
    private func cosineSimilarity(a: [Float], b: [Float]) -> Float {
        // 1. Dot Product
        let dotProduct: Float = zip(a, b).map(*).reduce(0.0, +)
        
        // 2. Magnitudes
        let sumSquaresA: Float = a.map { $0 * $0 }.reduce(0.0, +)
        let sumSquaresB: Float = b.map { $0 * $0 }.reduce(0.0, +)
        
        let magnitudeA = sqrt(sumSquaresA)
        let magnitudeB = sqrt(sumSquaresB)
        
        // 3. CRITICAL: Check for Zero Magnitude BEFORE division
        if magnitudeA == 0 || magnitudeB == 0 {
            return 0.0
        }
        
        // 4. Perform Division
        let result = dotProduct / (magnitudeA * magnitudeB)
        
        // 5. DOUBLE CHECK: If the result somehow became NaN, force it to 0.0
        if result.isNaN || result.isInfinite {
            return 0.0
        }
        
        return result
    }
    
    private func cleanText(_ text: String) -> String {
            var processed = text
            
            // 1. Remove the specific footer/header noise from your PDF
            // Note: I copied these patterns directly from your logs
            let noisePatterns = [
                "nimbleedge pvt. ltd.",
                "nimbleedge pvt. Itd.", // typo in PDF
                "\\+91 87179 83153",
                "sales@nimbleedge.com",
                "nimbleedge.com",
                "Data for Page No\\..*"
            ]
            
            for pattern in noisePatterns {
                processed = processed.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            }
            
            // 2. Collapse extra whitespace
            // This turns "Medical   \n   Leave" into "Medical Leave"
            processed = processed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            
            return processed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
}
