#!/bin/bash

# Download Gemma 3n E2B model for SafeGuard iOS integration
# This downloads the ~1GB GGUF quantized model for on-device inference

MODEL_URL="https://huggingface.co/google/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-q4_k_m.gguf"
MODEL_DIR="/Users/ezakas/SafeGuard-iOS/SafeGuardParent/SafeGuardParent/Models"
MODEL_FILE="$MODEL_DIR/gemma-3n-e2b.gguf"

echo "🤖 Downloading Gemma 2 2B model for SafeGuard iOS..."
echo "Target: $MODEL_FILE"
echo "Size: ~1.5GB (this may take a few minutes)"

# Create models directory if it doesn't exist
mkdir -p "$MODEL_DIR"

# Download the model
echo "Starting download..."
curl -L "$MODEL_URL" -o "$MODEL_FILE" --progress-bar

if [ $? -eq 0 ]; then
    echo "✅ Model download completed successfully!"
    echo "📁 Model saved to: $MODEL_FILE"
    echo "📊 File size: $(ls -lh "$MODEL_FILE" | awk '{print $5}')"
else
    echo "❌ Model download failed!"
    exit 1
fi

echo "🔧 Next steps:"
echo "1. Add llama.cpp framework to Xcode project"
echo "2. Update GemmaModel.swift to use actual llama.cpp inference"
echo "3. Test natural language commands with real model"