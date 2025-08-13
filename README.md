# WhisperKit Expo

A React Native Expo wrapper for [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Apple's on-device speech recognition framework.

**⚠️ iOS Only**: This package only supports iOS as WhisperKit is an Apple-specific framework.

## Features

- 🎙️ **File-based transcription** - Transcribe audio files with high accuracy
- 🌍 **Multi-language support** - Detect and transcribe in 30+ languages
- 📦 **Multiple models** - Choose from tiny to large models based on your needs
- ⚡ **Hardware acceleration** - Leverages Apple's Neural Engine for fast processing
- 🔄 **Automatic model downloads** - Models download automatically when first used

## Installation

```bash
npm install whisper-kit-expo
```

### iOS Setup

After installation, you need to:

1. Run `npx expo prebuild` to generate native iOS files
2. Navigate to the `ios` directory and run `pod install`
3. Add microphone permissions to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to microphone for speech recognition</string>
```

## Basic Usage

```typescript
import { transcribe, loadTranscriber } from 'whisper-kit-expo';

// Initialize the transcriber (downloads model on first run)
await loadTranscriber();

// Transcribe an audio file
const text = await transcribe('/path/to/audio.m4a');
console.log(text);
```

### Auto-initialization with Component

```typescript
import { TranscriberInitializer } from 'whisper-kit-expo';

function App() {
  return (
    <TranscriberInitializer>
      <YourApp />
    </TranscriberInitializer>
  );
}
```

## Model Selection

WhisperKit automatically downloads models from Hugging Face when you first use them. Models are cached locally for subsequent use.

```typescript
import { loadTranscriber } from 'whisper-kit-expo';

// Load a specific model (downloads automatically if not present)
await loadTranscriber({
  model: 'openai_whisper-base', // Model variant name
  prewarm: true
});
```

### Available Models

**English-only models** (smaller, faster for English):
- `tiny.en` (39MB) - Fastest English model
- `base.en` (74MB) - Good balance for English
- `small.en` (244MB) - More accurate English
- `medium.en` (769MB) - High accuracy English

**Multilingual models** (support 99 languages):
- `tiny` (39MB) - Fastest multilingual
- `base` (74MB) - Good balance (recommended to start)
- `small` (244MB) - More accurate
- `medium` (769MB) - High accuracy
- `large-v2` (1.5GB) - Previous best model
- `large-v3` (1.5GB) - Latest, most accurate
- `large-v3-turbo` (954MB) - Optimized large-v3

**Distilled models** (optimized for speed):
- `distil-large-v3` (756MB) - 2x faster than large-v3

### Model Variant Names

Use these exact names when loading models:
```
openai_whisper-tiny.en
openai_whisper-tiny
openai_whisper-base.en
openai_whisper-base
openai_whisper-small.en
openai_whisper-small
openai_whisper-medium.en
openai_whisper-medium
openai_whisper-large-v2
openai_whisper-large-v3
openai_whisper-large-v3_turbo
distil-whisper_distil-large-v3
```

## Advanced Transcription

```typescript
import { transcribeWithOptions } from 'whisper-kit-expo';

const result = await transcribeWithOptions('/path/to/audio.m4a', {
  language: 'es', // Force Spanish, or leave blank for auto-detect
  wordTimestamps: true, // Get word-level timing
  task: 'transcribe', // or 'translate' to English
  
  // Real-time progress updates
  progressCallback: (progress) => {
    console.log('Current text:', progress.text);
    console.log('Tokens:', progress.tokens.length);
    console.log('Avg log probability:', progress.avgLogprob);
    console.log('Compression ratio:', progress.compressionRatio);
  }
});

console.log(result.text); // Full transcription
console.log(result.language); // Detected language
console.log(result.segments); // Detailed segments with timestamps
```

## Language Detection

```typescript
import { detectLanguage, getSupportedLanguages } from 'whisper-kit-expo';

// Detect language from audio
const detection = await detectLanguage('/path/to/audio.m4a');
console.log(`Detected: ${detection.detectedLanguage}`);
console.log(`Probabilities:`, detection.languageProbabilities);

// Get all supported languages
const languages = getSupportedLanguages();
// { "en": "English", "es": "Spanish", "fr": "French", ... }
```

## Model Management

```typescript
import { getAvailableModels, downloadModel, deleteModel } from 'whisper-kit-expo';

// List available models
const models = await getAvailableModels();
models.forEach(model => {
  console.log(`${model.name}: ${model.description}`);
  console.log(`Downloaded: ${model.isDownloaded}`);
});

// Pre-download a model
await downloadModel('large-v3');

// Delete a model to free up space
await deleteModel('large-v3');
```

## API Reference

### Core Functions

#### `loadTranscriber(options?: ModelOptions): Promise<boolean>`
Initialize the transcriber with optional model configuration.

#### `transcribe(file: string): Promise<string>`
Simple transcription function that returns the transcribed text.

#### `transcribeWithOptions(file: string, options?: TranscriptionOptions): Promise<TranscriptionResult>`
Advanced transcription with options for language, timestamps, and more.

### Language Functions

#### `detectLanguage(file: string): Promise<LanguageDetectionResult | null>`
Detect the language of an audio file.

#### `getSupportedLanguages(): Record<string, string>`
Get all supported languages as ISO codes with names.

### Model Management

#### `getAvailableModels(): Promise<AvailableModel[]>`
Get list of available Whisper models.

#### `downloadModel(modelName: string): Promise<boolean>`
Pre-download a specific model.

#### `deleteModel(modelName: string): Promise<boolean>`
Delete a downloaded model.

### Utility Functions

#### `isTranscriberReady(): boolean`
Check if the transcriber is initialized and ready.

## Types

### ModelOptions
```typescript
type ModelOptions = {
  model?: string; // Model variant name
  downloadBase?: string;
  modelFolder?: string;
  prewarm?: boolean;
};
```

### TranscriptionOptions
```typescript
type TranscriptionOptions = {
  task?: 'transcribe' | 'translate';
  language?: string; // ISO 639-1 code
  temperature?: number;
  wordTimestamps?: boolean;
  // ... more options
};
```

### TranscriptionResult
```typescript
type TranscriptionResult = {
  text: string;
  segments: TranscriptionSegment[];
  language?: string;
};
```

## How Models Work

1. **First Use**: When you call `loadTranscriber()` with a model, WhisperKit checks if it exists locally
2. **Auto-Download**: If not present, it downloads from Hugging Face
3. **Local Cache**: Models are stored in `~/Documents/huggingface/models/`
4. **Reuse**: Subsequent uses load from cache instantly

## Performance Tips

1. **Model Selection**: 
   - Start with `base` for good balance
   - Use `.en` variants if you only need English
   - `distil-large-v3` offers large model quality at 2x speed

2. **Memory Usage**: Larger models require more memory
3. **First Run**: Initial model download may take time depending on size

## Supported Audio Formats

- WAV
- MP3
- M4A
- FLAC
- AAC (in M4A container)

## Requirements

- iOS 17.0+
- Expo SDK 53+
- React Native 0.76.6+

## Troubleshooting

### Model Download Issues
If models fail to download, check your internet connection and available storage space.

### Memory Warnings
For large models on older devices, you may need to use smaller models or close other apps.

### Audio Format Errors
Ensure your audio files are in a supported format and accessible at the provided path.

## License

MIT

## Credits

Built on top of [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax Inc.