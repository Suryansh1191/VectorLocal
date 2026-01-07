import SwiftUI
import PDFKit
import AppKit
import Vision

struct ContentView: View {
    @State private var selectedPDFURL: URL?
    @State private var pageSummaries: [Int: String] = [:] // Dictionary: pageNumber -> summary
    @State private var finalSummary: String = ""
    @State private var fileName: String = "No file selected"
    @State private var isProcessing: Bool = false
    @State private var currentStatus: String = ""
    @State private var processedPages: Int = 0
    @State private var totalPages: Int = 0
    @State private var showSummary: Bool = false
    @State private var chatMessages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSendingMessage: Bool = false
    @State private var extractionResults: [Int: (ocrText: String, ocrTime: TimeInterval)] = [:]
    @State private var extractionStats: (totalPages: Int, ocrTotalTime: TimeInterval, overallTime: TimeInterval)? = nil
    
    let embeddingEngine: EmbeddingEngine
    let ragEngine: RAGEngine
    let summarizer: PDFProcessor
    
    init() {
        let embeddingEngine = EmbeddingEngine()
        let ragEngine = RAGEngine(embeddingEngine: embeddingEngine)
        self.embeddingEngine = embeddingEngine
        self.ragEngine = ragEngine
        self.summarizer = PDFProcessor(ragEngine: ragEngine)
    }
    
    var body: some View {
        Group {
            if selectedPDFURL == nil {
                // Initial view - PDF selection
                initialView
            } else {
                // Chat-based view after PDF is selected
                chatView
            }
        }
        .onAppear {
            Task {
                do {
                    try await embeddingEngine.load()
                    try await embeddingEngine.debugEmbeddingEngine()
                } catch {
                    print("Error loading embeddingEngine: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Initial View
    private var initialView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("Select a PDF to get started")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Button(action: choosePDF) {
                Text("Choose PDF")
                    .font(.title3)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Chat View
    private var chatView: some View {
        VStack(spacing: 0) {
            // Header with PDF info and expandable summary
            headerView
            
            Divider()
            
            // Chat messages area
            chatMessagesView
            
            // Input area (for future chat functionality)
            chatInputView
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text("PDF")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                        
                        if isProcessing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Processing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Expandable extraction results button
                if !extractionResults.isEmpty || isProcessing {
                    Button(action: {
                        withAnimation {
                            showSummary.toggle()
                        }
                    }) {
                        Image(systemName: showSummary ? "chevron.up" : "chevron.down")
                            .foregroundColor(.accentColor)
                            .padding(8)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Expandable extraction results section
            if showSummary && (!extractionResults.isEmpty || extractionStats != nil) {
                Divider()
                VStack(spacing: 0) {
                    // Stats header
                    if let stats = extractionStats {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("OCR Extraction Statistics")
                                    .font(.headline)
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("OCR Total: \(String(format: "%.3f", stats.ocrTotalTime))s")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Average per page: \(String(format: "%.3f", stats.ocrTotalTime / Double(stats.totalPages)))s")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Overall: \(String(format: "%.3f", stats.overallTime))s")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Pages: \(stats.totalPages)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        
                        Divider()
                    }
                    
                    // Results display
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(extractionResults.keys.sorted()), id: \.self) { pageNumber in
                                if let result = extractionResults[pageNumber] {
                                    ExtractionResultView(
                                        pageNumber: pageNumber,
                                        ocrText: result.ocrText,
                                        ocrTime: result.ocrTime
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 400)
                    .background(Color(NSColor.textBackgroundColor))
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Chat Messages View
    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if chatMessages.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "message")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Start a conversation about your PDF")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(chatMessages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: chatMessages.count) { _ in
                if let lastMessage = chatMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Chat Input View
    private var chatInputView: some View {
        HStack(spacing: 12) {
            TextField("Ask questions about the PDF...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .disabled(isSendingMessage || isProcessing)
                .onSubmit {
                    sendMessage()
                }
            
            Button(action: sendMessage) {
                if isSendingMessage {
                    ProgressView()
                        .scaleEffect(0.7)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.accentColor.opacity(0.6))
                        .clipShape(Circle())
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingMessage || isProcessing)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    /// Opens a Finder-style dialog to choose a PDF file.
    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedPDFURL = url
            fileName = url.lastPathComponent
            
            // Reset state
            pageSummaries = [:]
            finalSummary = ""
            isProcessing = true
            currentStatus = "Loading PDF..."
            processedPages = 0
            totalPages = 0
            showSummary = false
            chatMessages = []
            extractionResults = [:]
            extractionStats = nil
            
            Task {
                do {
                    // Process PDF and generate summaries
                    for try await progress in await summarizer.startProcessing(from: url) {
                        await MainActor.run {
                            handleProgress(progress)
                        }
                    }
                    
                    await MainActor.run {
                        isProcessing = false
                        currentStatus = "Complete!"
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        currentStatus = "Error: \(error.localizedDescription)"
                        print("Error summarizing PDF: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    /// Handles progress updates from PDFSummarizer
    private func handleProgress(_ progress: SummaryProgress) {
        switch progress {
        case .extractionStarted:
            currentStatus = "Extracting text from PDF using OCR..."
            
        case .pageExtracted(let pageNumber, _):
            totalPages = max(totalPages, pageNumber)
            currentStatus = "Extracted page \(pageNumber) of \(totalPages)..."
            
        case .extractionComplete(let totalPages):
            self.totalPages = totalPages
            
        case .pageSummarized(let pageNumber, let summary):
            pageSummaries[pageNumber] = summary
            processedPages = pageSummaries.count
            currentStatus = "Summarized page \(pageNumber) of \(totalPages)..."
            print("✅ Page \(pageNumber) summary: \(summary.prefix(100))...")
            
        case .allPagesSummarized(let summaries):
            pageSummaries = summaries
            processedPages = summaries.count
            currentStatus = "Generating final summary..."
            finalSummary = "" // Reset to start fresh
            print("📚 All \(summaries.count) pages summarized, generating final summary...")
            
        case .finalSummaryToken(let token):
            // Append token to final summary in real-time
            finalSummary += token
            currentStatus = "Generating final summary..."
            
        case .finalSummaryComplete:
            currentStatus = "Summary complete!"
            print("🎉 Final summary generated!")
        case .pageExtractedOCR(pageNumber: let pageNumber):
            currentStatus = "OCR Done for pageNumber: \(pageNumber)"
            print("OCR Done for pageNumber: \(pageNumber)")

        }
    }
    
    /// Adds a chat message to the conversation
    private func addChatMessage(_ text: String, isUser: Bool) {
        let message = ChatMessage(text: text, isUser: isUser, timestamp: Date())
        chatMessages.append(message)
    }
    
    /// Sends a message and performs RAG search
    private func sendMessage() {
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty, !isSendingMessage, !isProcessing else { return }
        
        // Add user message to chat
        addChatMessage(messageText, isUser: true)
        
        // Clear input
        inputText = ""
        isSendingMessage = true
        
        // Perform RAG search
        Task {
            
            chatMessages.append(ChatMessage(text: "Generating...", isUser: false, timestamp: Date()))
            
            do {
                // for try await progress in await llmEngine.generate(
                for try await llmOutput in try await summarizer.prompt(text: messageText) {
                    if chatMessages.last?.text == "Generating..." {
                        chatMessages[chatMessages.count - 1] = ChatMessage(text: llmOutput, isUser: false, timestamp: Date())
                    } else {
                        chatMessages[chatMessages.count - 1].text.append(contentsOf: llmOutput)
                    }
                }
                
                isSendingMessage = false
            } catch {
                await MainActor.run {
                    isSendingMessage = false
                    print("❌ Error performing RAG search: \(error.localizedDescription)")
                    addChatMessage("Error searching the PDF: \(error.localizedDescription)", isUser: false)
                }
            }
        }
    }
}

// MARK: - Supporting Views and Models

struct ChatMessage: Identifiable {
    let id = UUID()
    var text: String
    let isUser: Bool
    let timestamp: Date
}

struct ChatBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.isUser
                            ? Color.accentColor
                            : Color(NSColor.controlBackgroundColor)
                    )
                    .foregroundColor(
                        message.isUser
                            ? .white
                            : .primary
                    )
                    .cornerRadius(12)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 600, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

// MARK: - Extraction Result View
struct ExtractionResultView: View {
    let pageNumber: Int
    let ocrText: String
    let ocrTime: TimeInterval
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Page \(pageNumber)")
                    .font(.headline)
                Spacer()
                Text("OCR: \(String(format: "%.3f", ocrTime))s")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("OCR Text Extraction")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                Text(ocrText.isEmpty ? "[No text found]" : ocrText)
                    .font(.caption)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
