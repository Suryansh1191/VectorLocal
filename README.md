# LocalVector: Offline PDF Intelligence

**A native Swift application for chatting with and summarizing massive documents (1000+ pages) locally on Apple Silicon.**

![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square) ![Platform](https://img.shields.io/badge/Platform-macOS%2014.0+-lightgrey?style=flat-square) ![Engine](https://img.shields.io/badge/MLX-Apple_Silicon_Optimized-blue?style=flat-square) ![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

### 🚀 Overview
**LocalVector** is a high-performance macOS app that brings Large Language Model (LLM) capabilities to your local documents. Unlike web-based tools, this app processes sensitive PDFs entirely on-device using the **MLX** framework and **Qwen 2.5-3B** model. It features a custom-built ingestion pipeline that intelligently switches between digital text extraction and GPU-accelerated OCR to handle everything from perfect e-books to noisy scanned contracts.

### ✨ Key Features

* **🔒 100% Local & Private:** No API keys, no cloud servers. Your data never leaves your M-series Mac.
* **🧠 Intelligent "Hybrid" Ingestion:**
    * Automatically detects corrupted or "gibberish" text layers in PDFs.
    * Seamlessly falls back to **Apple Vision OCR** for scanned or flattened pages.
    * Includes a custom image enhancement pipeline (Contrast/Sharpening) to clean up noisy scans before processing.
* **⚡ Optimized Performance:**
    * Runs **Qwen 2.5-3B-Instruct (4-bit quantized)** with minimal memory footprint (~2.5GB RAM).
    * Utilizes **Swift Actors** for thread-safe, non-blocking background processing of 1000+ page documents.
    * Implements recursive text chunking for context-aware RAG (Retrieval Augmented Generation).
* **📄 Smart Summarization:** Generates chapter-wise or full-document summaries using map-reduce logic suitable for long-context windows.

### 🛠️ Tech Stack

* **Language:** Swift 5.9 (SwiftUI)
* **Inference Engine:** [MLX Swift](https://github.com/ml-explore/mlx-swift) (Apple's array framework for machine learning)
* **Vision & Graphics:** PDFKit, Vision Framework, Core Image, Core Graphics
* **Model:** Qwen 2.5-3B-Instruct (4-bit)

### 🏗️ Architecture Highlights

1.  **The Actor Model:** A dedicated `PDFProcessor` actor handles safe concurrency, ensuring the UI never freezes during heavy OCR tasks.
2.  **Coordinate Handling:** Uses `NSImage.lockFocus()` to eliminate common coordinate flipping/mirroring issues found in standard `CGContext` implementations.
3.  **Semantic Validation:** Ingestion logic checks for English sentence structure and stop-words to reject garbage text layers often found in older PDFs.

### 📦 Installation

1.  Clone the repository.
2.  Download the **Qwen 2.5-3B-Instruct-4bit** model files (`safetensors`, `config`, `tokenizer`) from Hugging Face.
3.  Place the model folder in the project root and ensure it is added as a **Folder Reference (Blue Folder)** in Xcode.
4.  Build and run on any Mac with Apple Silicon (M1/M2/M3/M4).

### 🤝 Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.
