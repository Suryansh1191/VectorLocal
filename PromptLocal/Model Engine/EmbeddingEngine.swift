import Foundation
import CoreML
import Tokenizers // Provided by swift-transformers

actor EmbeddingEngine {
    
    // MARK: - Properties
    private var model: MLModel?
    private var tokenizer: Tokenizer?
    
    // MARK: - Lifecycle
    init() {}
    
    func load() async throws {
        // 1. Locate the local folder in the Bundle
        guard let tokenizerFolder = Bundle.main.url(forResource: "bert-tokenizer", withExtension: nil) else {
            throw NSError(domain: "CoreMLEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tokenizer folder not found in Bundle"])
        }
        
        // 2. Load Tokenizer from the local folder
        // Note: This API requires swift-transformers v1.0+
        self.tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerFolder)
        
        
        // 2. Load Core ML Model
        // Assumes you dragged "MiniLM.mlpackage" into your Xcode project bundle
        guard let modelURL = Bundle.main.url(forResource: "MiniLM", withExtension: "mlmodelc") else {
            throw NSError(domain: "CoreMLEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "MiniLM.mlmodelc not found"])
        }
        
        // Configure to use the Neural Engine (ANE)
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        print("✅ Core ML Model Loaded")
    }
    
    // MARK: - Main Function
    func embed(text: String) async throws -> [Float] {
        guard let model = self.model, let tokenizer = self.tokenizer else {
            throw NSError(domain: "CoreMLEngine", code: 500, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        
        // 1. Tokenize
        let tokens = tokenizer.encode(text: text)
        let seqLen = tokens.count
        
        // 2. Prepare Core ML Inputs
        // Shape: [1, seqLen] -> We use NSNumber for Core ML dimensions
        let shape = [1, NSNumber(value: seqLen)] as [NSNumber]
        
        let inputIDsArray = try MLMultiArray(shape: shape, dataType: .int32)
        let maskArray = try MLMultiArray(shape: shape, dataType: .int32)
        
        // We must use the [0, i] index to fill the columns of the first row.
        for (i, token) in tokens.enumerated() {
            let index = [0, NSNumber(value: i)] as [NSNumber]
            
            inputIDsArray[index] = NSNumber(value: token)
            maskArray[index] = 1 // 1 = Real token
        }
        
        // 3. Run Prediction
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDsArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray)
        ])
        
        let output = try await model.prediction(from: inputs)
        print("output: \(output)")
        
        // 4. Extract Hidden State
        guard let hiddenState = output.featureValue(for: "last_hidden_state")?.multiArrayValue else {
            throw NSError(domain: "CoreMLEngine", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid Output"])
        }
                
        // 5. Process
        return processOutput(hiddenState: hiddenState, seqLen: seqLen)
    }
    
    // MARK: - Math Helper (Mean Pooling + L2 Norm)
    private func processOutput(hiddenState: MLMultiArray, seqLen: Int) -> [Float] {
        let hiddenSize = 384
        var pooledVector = [Float](repeating: 0.0, count: hiddenSize)
        
        // Fallback for Float16 (common in quantized models)
        // We iterate safely to avoid pointer crashing
        for i in 0..<seqLen {
            for j in 0..<hiddenSize {
                // Using linear index calculation for safety if shape is [1, seq, 384]
                let linearIndex = (i * hiddenSize) + j
                let val = hiddenState[linearIndex].floatValue
                pooledVector[j] += val
            }
        }
        for j in 0..<hiddenSize {
            pooledVector[j] /= Float(seqLen)
        }
        
        // L2 NORMALIZATION
        let sumSquares = pooledVector.reduce(0) { $0 + ($1 * $1) }
        let magnitude = sqrt(sumSquares)
        let epsilon: Float = 1e-9
        let safeMagnitude = max(magnitude, epsilon)
        
        return pooledVector.map { $0 / safeMagnitude }
    }
    
    
    func debugEmbeddingEngine() async throws {
            print("🕵️‍♂️ TESTING EMBEDDING ENGINE...")
            
            let textA = "Apple"
            let textB = "Banana"
            
            let vectorA = try await embed(text: textA)
            let vectorB = try await embed(text: textB)
            
            // 1. Check if they are empty
            let magA = vectorA.map { $0 * $0 }.reduce(0, +)
            print("📊 Magnitude of 'Apple': \(magA)")
            
            if magA == 0 {
                print("❌ CRITICAL: The model returned a vector of all ZEROS.")
                return
            }
            
            // 2. Check if they are identical
            // We calculate similarity between "Apple" and "Banana"
            let similarity = cosineSimilarity(a: vectorA, b: vectorB)
            print("🎯 Similarity between 'Apple' and 'Banana': \(similarity)")
            
            if similarity > 0.99 {
                print("❌ CRITICAL: 'Apple' and 'Banana' are 99% identical.")
                print("👉 YOUR MODEL IS FROZEN. It returns the same vector for everything.")
            } else {
                print("✅ Model seems okay. Similarity is realistic (should be around 0.4 - 0.7).")
            }
        }
    
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
}
