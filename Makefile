# --- Configuration ---

# The Repository ID on Hugging Face (e.g. "bert-base-uncased")
MODEL_REPO := mlx-community/Qwen2.5-3B-4bit

# The specific path where you want the folder contents
# Example: ./MyApp.app/Contents/Resources/bert-model
TARGET_DIR := PromptLocal/Models/qwen2.5-3b-4bit

# Optional: Specific revision (branch, tag, or commit hash). Defaults to main.
REVISION := main

# --- Targets ---

.PHONY: model clean check-tools
# Default target
model: check-cli
	@echo "----------------------------------------"
	@echo "Target Directory: $(TARGET_DIR)"
	@echo "Downloading model repository: $(MODEL_REPO)..."
	@echo "----------------------------------------"
	@# --local-dir-use-symlinks False ensures real files (crucial for macOS bundles)
	huggingface-cli download $(MODEL_REPO) \
		--local-dir $(TARGET_DIR) \
		--revision $(REVISION) \
		--local-dir-use-symlinks False \
		--exclude "*.git*"
	@echo "----------------------------------------"
	@echo "✅ Download complete! Model stored in: $(TARGET_DIR)"

# Verify the CLI tool is installed and in your PATH
check-cli:
	@command -v huggingface-cli >/dev/null 2>&1 || \
		(echo "❌ Error: 'huggingface-cli' command not found." && \
		 echo "   Please install it running: pip install 'huggingface_hub[cli]'" && \
		 echo "   (Ensure your Python bin folder is in your PATH)" && \
		 exit 1)

clean:
	@echo "Removing model directory..."
	rm -rf $(TARGET_DIR)
	@echo "Done."
