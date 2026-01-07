import PDFKit
import Vision

/// A dedicated worker class for handling PDF text extraction safely and efficiently.
actor PDFTextExtractor  {
    
    // MARK: - Public API
    
    /// Extracts text from a PDF URL using OCR.
    /// Returns an AsyncStream that yields (pageNumber, text) tuples as each page is processed.
    func extractText(from url: URL) -> AsyncThrowingStream<(Int, String), Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let document = PDFDocument(url: url) else {
                    continuation.finish(throwing: NSError(domain: "PDFProcessor", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF document"]))
                    return
                }

                let totalPages = document.pageCount
                let maxConcurrency = 5
                
                await withTaskGroup(of: (Int, String).self) { group in
                    var nextPageIndex = 0
                    
                    // Helper to add a task for a specific page index
                    func addNextTask() {
                        guard nextPageIndex < totalPages else { return }
                        
                        let currentIndex = nextPageIndex
                        nextPageIndex += 1
                        
                        guard let page = document.page(at: currentIndex) else {
                            // If a page is nil, skip it and try adding the next one immediately
                            // to keep the buffer full.
                            addNextTask()
                            return
                        }
                        
                        group.addTask {
                            let text = await self.performOCR(on: page)
                            // Return (Page Number [1-based], Extracted Text)
                            return (currentIndex + 1, text)
                        }
                    }
                    
                    // 1. Initial Fill: Start the first 5 pages (or fewer if doc is small)
                    for _ in 0..<min(maxConcurrency, totalPages) {
                        addNextTask()
                    }
                    
                    // 2. Sliding Window: Wait for results one by one
                    // 'for await' pulls the next completed task from the group
                    for await result in group {
                        // Yield the result immediately
                        continuation.yield(result)
                        
                        // As soon as one task finishes, add the next page (if any left)
                        addNextTask()
                    }
                }
                
                // All tasks completed
                continuation.finish()
            }
        }
    }
    
    // MARK: - Core Rendering & OCR
    
    /// Converts PDFPage directly to CGImage (High Performance, No NSImage overhead)
    private func pdfPageToCGImage(page: PDFPage) -> CGImage? {
        // 1. Get the page size
        let pageBounds = page.bounds(for: .mediaBox)
        
        // 2. Define High-Res Scale (3.0 = 216 DPI, ideal for OCR)
        let scale: CGFloat = 3.0
        let newSize = NSSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        
        // 3. Create NSImage (Native macOS image handler)
        let image = NSImage(size: newSize)
        
        // 4. Lock Focus: This automatically sets up the correct CTM (Transformation Matrix)
        //    It handles the weird "Bottom-Left" vs "Top-Left" math for us.
        image.lockFocus()
        
        // A. Get the context created by lockFocus
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        
        // B. Set White Background (Crucial: PDFs are transparent by default)
        context.setFillColor(CGColor.white)
        context.fill(CGRect(origin: .zero, size: newSize))
        
        // C. Setup Quality
        context.interpolationQuality = .high
        
        // D. Apply Scale so the PDF draws larger
        //    (We do NOT manually flip x/y here, AppKit does it for us)
        context.scaleBy(x: scale, y: scale)
        
        // E. Handle Page Rotation (The Step we missed before)
        //    Some PDFs are stored sideways (90deg) but displayed upright.
        //    draw(with:to:) respects this automatically.
        page.draw(with: .mediaBox, to: context)
        
        image.unlockFocus()
        
        // 5. Return the CGImage for Vision
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    private func performOCR(on page: PDFPage) async -> String {
        // 1. Render to image (keep your existing helper)
        guard let cgImage = pdfPageToCGImage(page: page) else { return "" }
        
        return await Task.detached(priority: .userInitiated) {
            // We run this in a detached task because Vision is CPU-intensive
            // and 'perform' is synchronous (blocking).
            
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate // Best results
            request.usesLanguageCorrection = true // Fixes spelling based on context
            
            // This is crucial for "Human Understandable" results:
            // It tells Vision to treat the text as lines in a document, not loose words.
            request.recognitionLanguages = ["en-US"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
                
                guard let observations = request.results else { return "" }
                
                // 2. Post-Process for "Human Readability"
                // Vision returns lines. We want to reconstruct paragraphs.
                var resultText = ""
                var previousY: CGFloat = 1.0 // Start at top (Vision coords are 0-1)
                
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    
                    // Detect Paragraph Breaks
                    // If the vertical gap between this line and the previous one is large (> 2% of page height),
                    // assume it's a new paragraph.
                    let currentY = observation.boundingBox.maxY
                    let gap = previousY - currentY
                    
                    if gap > 0.02 {
                        resultText += "\n\n" // Double newline for paragraph
                    } else {
                        resultText += "\n"   // Single newline for line break
                    }
                    
                    resultText += topCandidate.string
                    previousY = observation.boundingBox.minY
                }
                
                return resultText.trimmingCharacters(in: .whitespacesAndNewlines)
                
            } catch {
                print("OCR Failed: \(error)")
                return ""
            }
        }.value
    }
}
