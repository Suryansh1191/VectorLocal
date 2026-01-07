# VectorLocal: Offline PDF Intelligence

**A native Swift based macOS application for chatting with and summarizing massive documents (100+ pages) locally on Apple Silicon.**

![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square) ![Platform](https://img.shields.io/badge/Platform-macOS%2014.0+-lightgrey?style=flat-square) ![Engine](https://img.shields.io/badge/MLX-Apple_Silicon_Optimized-blue?style=flat-square) ![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

### 🚀 Overview
**VectorLocal** is a high-performance macOS app that brings Large Language Model (LLM) and RAG capabilities to your local documents. Unlike web-based tools, this app processes sensitive PDFs entirely on-device using the **MLX** framework for running **Qwen 2.5-3B** mode on-device and uses CoreML for running *all-MiniLM-L6-v2* embedding for creating vector-based embedding. 

### ✨ Key Features

* **🔒 100% Local & Private:** No API keys, no cloud servers. Your data never leaves your M-series Mac.
* **🧠 Intelligent "Hybrid" Ingestion:**
    * Automatically detects corrupted or "gibberish" text layers in PDFs.
    * Seamlessly falls back to **Apple Vision OCR** for scanned or flattened pages.
    * Includes a custom image enhancement pipeline (Contrast/Sharpening) to clean up noisy scans before processing.
* **⚡ Optimized Performance:**
    * Runs **Qwen 2.5-3B-Instruct (4-bit quantized)** with minimal memory footprint (~2.5GB RAM).
    * Implements recursive text chunking for context-aware RAG (Retrieval Augmented Generation).
* **📄 Smart Summarization:** Generates chapter-wise or full-document summaries using map-reduce logic suitable for long-context windows.

### 🛠️ Tech Stack

* **Language:** Swift 5.9 (SwiftUI)
* **Inference Engine:** [MLX Swift](https://github.com/ml-explore/mlx-swift) (Apple's array framework for machine learning)
* **Vision & Graphics:** PDFKit, Vision Framework, Core Image, Core Graphics
* **LLM Model:** Qwen 2.5-3B-Instruct (4-bit)
* **Embadding Model:** all-MiniLM-L6-v2

### 🏗️ Architecture Flow
* Document Pre-Processing
![Untitled Diagram (1)](https://github.com/user-attachments/assets/6a57bd46-9197-4a4b-a638-c66244dc6f87)

* Prompt Processing
![Untitled Diagram (1)](https://github.com/user-attachments/assets/75924718-7280-48a6-9e57-c33a9f570989)


### 📦 Installation

1.  Clone the repository.
2.  Download the **Qwen 2.5-3B-Instruct-4bit** model files (`safetensors`, `config`, `tokenizer`) from Hugging Face.
3.  Place the model folder in the project root and ensure it is added as a **Folder Reference (Blue Folder)** in Xcode.
4.  Build and run on any Mac with Apple Silicon (M1/M2/M3/M4).

### 🤝 Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.
