import Foundation
import PDFKit

/// A class that extracts text from a PDF, summarizes each page, and then generates a final summary.
actor PDFProcessor {
    
    private let pdfProcessor: PDFTextExtractor 
    private let llmEngine: LLMEngine
    private let ragEngine: RAGEngine?
    
    init(
        pdfProcessor: PDFTextExtractor  = PDFTextExtractor (),
        llmEngine: LLMEngine = LLMEngine(),
        ragEngine: RAGEngine? = nil
    ) {
        self.pdfProcessor = pdfProcessor
        self.llmEngine = llmEngine
        self.ragEngine = ragEngine
    }
    
    /// Extracts text from a PDF using OCR only.
    func startProcessing(from url: URL) -> AsyncThrowingStream<SummaryProgress, Error> {
        
        Task {
            try? await llmEngine.loadModel()
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Load PDF document
                    guard let document = PDFDocument(url: url) else {
                        continuation.finish(throwing: NSError(domain: "PDFSummarizer", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF document"]))
                        return
                    }
                    
                    let totalPages = document.pageCount
                    continuation.yield(.extractionStarted)
                    
                    let ocrText: [(Int, String)] = []
                    for try await progress in await pdfProcessor.extractText(from: url) {
                        try await ragEngine?.add(text: progress.1)
                    }
                                        
                    continuation.yield(.extractionComplete(
                        totalPages: totalPages,
                    ))
                    
                    continuation.finish()
                } catch {
                    print("❌ Error during PDF extraction: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func prompt(text: String) async throws -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // 1. Retrieve relevant chunks (The "Knowledge")
                    // Increase limit if you have a large context window (e.g., 4-6 chunks)
                    guard let chunks = try await ragEngine?.search(query: text, limit: 5) else {
                        continuation.finish(throwing: NSError(domain: "RAG", code: 404, userInfo: [NSLocalizedDescriptionKey: "RAG Engine not ready"]))
                        return
                    }
                    
                    // 2. Format the Context String
                    // Join all chunks with newlines and markers
                    let contextString = chunks
                        .map { $0.text }
                        .joined(separator: "\n\n---\n\n")
                    
                    // 3. Create the System Prompt (The "Rules")
                    let systemPrompt = """
                        You are a precise and helpful assistant.
                        Use the provided context documents below to answer the user's question.
                        
                        Rules:
                        1. Answer strictly based on the context provided, but make sure you explain those answers.
                        2. If the answer is not in the context, say "I cannot find that information in the documents."
                        3. Do not make up facts or use outside knowledge.
                        4. Keep your answer concise and direct.
                        """
                    
                    // 4. Create the User Prompt (The "Input")
                    let finalUserPrompt = """
                        Context information is below:
                        ---------------------
                        \(contextString)
                        ---------------------
                        
                        Question: \(text)
                        
                        Answer:
                        """
                    
                    print("FinalUserPrompt: \(finalUserPrompt)")
                    
                    // 5. Generate Response
                    // Pass the constructed prompt to your LLM
                    for try await progress in await llmEngine.generate(
                        prompt: finalUserPrompt,
                        systemPrompt: systemPrompt
                    ) {
                        continuation.yield(progress)
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
}

/// Progress updates during PDF summarization.
enum SummaryProgress {
    case extractionStarted
    case pageExtracted(pageNumber: Int, text: String)
    case pageExtractedOCR(pageNumber: Int)
    case extractionComplete(totalPages: Int)
    case pageSummarized(pageNumber: Int, summary: String)
    case allPagesSummarized(summaries: [Int: String])
    case finalSummaryToken(token: String)  // Streams tokens as they're generated
    case finalSummaryComplete  // Signals that final summary generation is complete
}

