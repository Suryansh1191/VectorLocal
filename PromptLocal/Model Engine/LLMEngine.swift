import Foundation
import MLX
import MLXLLM
import MLXLMCommon

actor LLMEngine {
    
    // MARK: - Configuration
    // If bundling: Use Bundle.main.url...
    // If downloading: Use the HuggingFace ID directly
    private var modelPath: URL?
    
    private var modelContainer: ModelContainer?
    private var isLoaded: Bool = false
    
    init(modelPath: String = "qwen2.5-3b-4bit") {
        self.modelPath = Bundle.main.url(forResource: "qwen2.5-3b-4bit", withExtension: nil)
    }
    
    // MARK: - Lifecycle
    
    /// Loads the Qwen model into Unified Memory (RAM)
    func loadModel() async throws {
        if isLoaded { return }
        
        guard let modelDir = modelPath else {
            throw NSError(domain: "LLMEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model folder not found in Bundle"])
        }
        
        // Configuration points to local folder
        let configuration = ModelConfiguration(directory: modelDir)
        
        // Load Model & Tokenizer
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
        ) { progress in
            print("Loading Qwen: \(Int(progress.fractionCompleted * 100))%")
        }
        
        self.modelContainer = container
        self.isLoaded = true
        print("Qwen 2.5 Loaded Successfully")
    }
    
    // MARK: - Core Generation
    
    /// Generates a summary or answer. Returns an AsyncStream for real-time UI updates.
    func generate(prompt: String, systemPrompt: String = "You are a helpful assistant.") -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let container = self.modelContainer else {
                    continuation.finish(throwing: NSError(domain: "LLMEngine", code: 500, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]))
                    return
                }
                
                // 1. Apply Chat Template
                let messages = [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": prompt]
                ]
                
                // 2. Perform Generation Context
                try await container.perform { context in
                    
                    // A. Prepare Input
                    let promptTokens = try context.tokenizer.applyChatTemplate(messages: messages)
                    let input = LMInput(tokens: MLXArray(promptTokens))
                    
                    // B. Configure Parameters
                    // Note: We tell the iterator specifically what strings should stop generation
                    let parameters = GenerateParameters(
                        maxTokens: 2048,
                        temperature: 0.3,
                        topP: 0.9
                    )
                    
                    // C. Call the function you found
                    let resultStream = try MLXLMCommon.generate(
                        input: input,
                        parameters: parameters,
                        context: context
                    )
                    
                    // D. Loop through the stream
                    // 'generation' is an object that contains the decoded text string
                    for await generation in resultStream {
                        if let text = generation.chunk {
                            
                            // Qwen uses special tags. If we see them, we stop.
                            if text.contains("<|im_end|>") || text.contains("<|endoftext|>") {
                                break
                            }
                            
                            // Otherwise, send text to UI
                            continuation.yield(text)
                        }
                    }
                }
                
                continuation.finish()
            }
        }
    }
}
