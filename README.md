# WhisperKit Expo

A comprehensive React Native Expo wrapper for [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Apple's on-device speech recognition framework. This package provides powerful transcription capabilities with support for streaming, multiple models, and advanced configuration options.

**⚠️ iOS Only**: This package only supports iOS as WhisperKit is an Apple-specific framework.

## Features

- 🎙️ **File-based transcription** - Transcribe audio files with high accuracy
- 🔄 **Live streaming transcription** - Real-time transcription during recording
- 📊 **Progress tracking** - Monitor transcription progress with detailed callbacks
- 🌍 **Multi-language support** - Detect and transcribe in 30+ languages
- 📦 **Model management** - Download, select, and manage different Whisper models
- ⏱️ **Word-level timestamps** - Get precise timing for each word
- 🎯 **Confidence scores** - Access probability scores for transcriptions
- ⚡ **Hardware acceleration** - Leverage Apple's Neural Engine for fast processing

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

### Simple Transcription

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

## Advanced Features

### Model Selection and Configuration

```typescript
import { loadTranscriber, ModelConfigurations } from 'whisper-kit-expo';

// Load a specific model
await loadTranscriber({
  model: 'openai/whisper-small',
  computeUnits: 'cpuAndNeuralEngine',
  prewarm: true,
  load: true
});

// Or use preset configurations
await loadTranscriber(ModelConfigurations.distilLarge);
```

Available models:
- `tiny` - 39MB, fastest, English only
- `base` - 74MB, fast, multilingual
- `small` - 244MB, balanced
- `medium` - 769MB, accurate
- `large-v3` - 1.5GB, most accurate
- `distil-large-v3` - 756MB, optimized large model

### Transcription with Options and Progress

```typescript
import { transcribeWithOptions, DecodingPresets } from 'whisper-kit-expo';

const result = await transcribeWithOptions('/path/to/audio.m4a', {
  // Language options
  language: 'es', // Force Spanish
  detectLanguage: true, // Or auto-detect
  
  // Quality options
  temperature: 0.0,
  compressionRatioThreshold: 2.4,
  logProbThreshold: -1.0,
  noSpeechThreshold: 0.6,
  
  // Features
  wordTimestamps: true,
  task: 'transcribe', // or 'translate' to English
  
  // Progress callback
  progressCallback: (progress) => {
    console.log(`Progress: ${progress.progress * 100}%`);
    console.log(`Current text: ${progress.text}`);
  }
});

console.log(result.text);
console.log(result.segments); // Detailed segments with timestamps
console.log(result.language); // Detected language
```

### Streaming Transcription

```typescript
import { startStreaming, stopStreaming } from 'whisper-kit-expo';

// Start streaming with configuration
await startStreaming(
  {
    sampleRate: 16000,
    numberOfChannels: 1,
    bufferDuration: 1.0,
  },
  (update) => {
    console.log(`Partial: ${update.isPartial}`);
    console.log(`Text: ${update.text}`);
    console.log(`Current time: ${update.currentTime}`);
  }
);

// Stop streaming and get final result
const finalResult = await stopStreaming();
console.log(finalResult.fullTranscription);
```

### Model Management

```typescript
import { 
  getAvailableModels, 
  downloadModel, 
  deleteModel,
  cancelModelDownload 
} from 'whisper-kit-expo';

// List available models
const models = await getAvailableModels();
models.forEach(model => {
  console.log(`${model.name}: ${model.description}`);
  console.log(`Size: ${model.size / 1024 / 1024}MB`);
  console.log(`Downloaded: ${model.isDownloaded}`);
});

// Download a specific model
await downloadModel('large-v3', (progress) => {
  console.log(`Downloading: ${progress.progress * 100}%`);
  console.log(`${progress.downloadedBytes} / ${progress.totalBytes}`);
});

// Cancel download
cancelModelDownload();

// Delete a model
await deleteModel('large-v3');
```

### Language Detection

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

### Word-Level Timestamps

```typescript
const result = await transcribeWithOptions('/path/to/audio.m4a', {
  wordTimestamps: true
});

result.segments.forEach(segment => {
  console.log(`Segment: ${segment.text}`);
  segment.words?.forEach(word => {
    console.log(`  "${word.word}" at ${word.start}s - ${word.end}s`);
  });
});
```

## API Reference

### Core Functions

#### `loadTranscriber(options?: ModelOptions): Promise<boolean>`
Initialize the transcriber with optional model configuration.

#### `transcribe(file: string): Promise<string>`
Simple transcription function (backward compatible).

#### `transcribeWithOptions(file: string, options?: TranscriptionOptions): Promise<TranscriptionResult>`
Advanced transcription with full options and callbacks.

### Streaming Functions

#### `startStreaming(config?: AudioStreamConfig, onUpdate?: StreamingListener): Promise<boolean>`
Start live transcription from microphone.

#### `stopStreaming(): Promise<StreamingResult | null>`
Stop streaming and get the final transcription.

#### `feedAudioData(audioData: ArrayBuffer): Promise<void>`
Feed audio data manually for streaming transcription.

### Model Management

#### `getAvailableModels(): Promise<AvailableModel[]>`
Get list of available Whisper models.

#### `downloadModel(modelName: string, onProgress?: DownloadListener): Promise<boolean>`
Download a specific model with progress tracking.

#### `deleteModel(modelName: string): Promise<boolean>`
Delete a downloaded model.

#### `cancelModelDownload(): void`
Cancel ongoing model download.

### Language Functions

#### `detectLanguage(file: string): Promise<LanguageDetectionResult | null>`
Detect the language of an audio file.

#### `getSupportedLanguages(): Record<string, string>`
Get all supported languages as ISO codes with names.

### Utility Functions

#### `isTranscriberReady(): boolean`
Check if the transcriber is initialized and ready.

#### `cleanup(): void`
Remove all event listeners (call on unmount).

## Types

### ModelOptions
```typescript
type ModelOptions = {
  model?: string;
  downloadBase?: string;
  modelFolder?: string;
  modelRepo?: string;
  computeUnits?: 'cpuOnly' | 'cpuAndGPU' | 'cpuAndNeuralEngine' | 'all';
  prewarm?: boolean;
  load?: boolean;
};
```

### TranscriptionOptions
```typescript
type TranscriptionOptions = {
  // Task
  task?: 'transcribe' | 'translate';
  
  // Language
  language?: string;
  detectLanguage?: boolean;
  
  // Quality
  temperature?: number;
  compressionRatioThreshold?: number;
  logProbThreshold?: number;
  noSpeechThreshold?: number;
  
  // Features
  wordTimestamps?: boolean;
  withoutTimestamps?: boolean;
  
  // Callbacks
  progressCallback?: (progress: TranscriptionProgress) => void;
  streamingCallback?: (update: StreamingTranscriptionUpdate) => void;
  
  // Performance
  concurrentWorkerCount?: number;
  chunkingStrategy?: 'vad' | 'fixed';
};
```

### TranscriptionSegment
```typescript
type TranscriptionSegment = {
  id: number;
  start: number;
  end: number;
  text: string;
  tokens: number[];
  temperature: number;
  avgLogprob: number;
  compressionRatio: number;
  noSpeechProb: number;
  words?: WordTiming[];
};
```

## Presets

The package includes convenient presets for common use cases:

```typescript
import { DecodingPresets } from 'whisper-kit-expo';

// For highest accuracy
await transcribeWithOptions(file, DecodingPresets.accurate);

// For fastest processing
await transcribeWithOptions(file, DecodingPresets.fast);

// For streaming
await transcribeWithOptions(file, DecodingPresets.streaming);
```

## Performance Tips

1. **Model Selection**: Start with smaller models (`tiny`, `base`) and upgrade if needed
2. **Compute Units**: Use `cpuAndNeuralEngine` for best performance/battery balance
3. **Streaming**: Disable `wordTimestamps` for lower latency
4. **Batch Processing**: Process multiple files sequentially, not in parallel

## Error Handling

```typescript
try {
  const text = await transcribe(file);
} catch (error) {
  if (error.message.includes('loadTranscriber')) {
    // Model not loaded
  } else if (error.message.includes('audio format')) {
    // Unsupported audio format
  }
}
```

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

## License

MIT

## Credits

Built on top of [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax Inc.