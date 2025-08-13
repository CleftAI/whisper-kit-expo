// Import the native module. On web, it will be resolved to WhisperKitExpo.web.ts
// and on native platforms to WhisperKitExpo.ts
import { 
  TranscribeResult,
  TranscriptionSegment,
  WordTiming,
  TranscriptionProgress,
  StreamingTranscriptionUpdate,
  DecodingOptions,
  ModelOptions,
  AudioStreamConfig,
  TranscriptionOptions,
  ModelDownloadProgress,
  AvailableModel,
  LanguageDetectionResult 
} from './WhisperKitExpo.types';
import WhisperKitExpoModule from './WhisperKitExpoModule';
import { TranscriberInitializer } from './TranscriberInitializer';
import { NativeEventEmitter, Platform } from 'react-native';

// Create event emitter for native events
const eventEmitter = Platform.OS !== 'web' ? new NativeEventEmitter(WhisperKitExpoModule) : null;

// Event listener types
export type ProgressListener = (progress: TranscriptionProgress) => void;
export type StreamingListener = (update: StreamingTranscriptionUpdate) => void;
export type DownloadListener = (progress: ModelDownloadProgress) => void;

// Backward compatible simple transcribe function
export async function transcribe(file: string): Promise<string> {
  const fileRegex = /^file:\/\//;
  const path = file.replace(fileRegex, "");
  const result: TranscribeResult = await WhisperKitExpoModule.transcribe(path);
  if (result.success) {
    console.log("Transcription is", result.value);
    return result.value;
  } else {
    throw new Error(result.value);
  }
}

// Enhanced transcribe with options
export async function transcribeWithOptions(
  file: string,
  options?: TranscriptionOptions
): Promise<{
  text: string;
  segments: TranscriptionSegment[];
  language?: string;
}> {
  const fileRegex = /^file:\/\//;
  const path = file.replace(fileRegex, "");
  
  // Set up progress callback if provided
  let progressSubscription: any;
  if (options?.progressCallback && eventEmitter) {
    progressSubscription = eventEmitter.addListener(
      'onTranscriptionProgress',
      options.progressCallback
    );
  }
  
  try {
    const result = await WhisperKitExpoModule.transcribeWithOptions(path, options);
    if (!result.success) {
      throw new Error(result.error || 'Transcription failed');
    }
    
    return {
      text: result.text,
      segments: result.segments,
      language: result.language
    };
  } finally {
    // Clean up event listener
    if (progressSubscription) {
      progressSubscription.remove();
    }
  }
}

// Model loading with options
export async function loadTranscriber(options?: ModelOptions): Promise<boolean> {
  return await WhisperKitExpoModule.loadTranscriber(options);
}

// Streaming transcription functions
export async function startStreaming(
  config?: AudioStreamConfig,
  onUpdate?: StreamingListener
): Promise<boolean> {
  if (onUpdate && eventEmitter) {
    eventEmitter.addListener('onStreamingUpdate', onUpdate);
  }
  
  return await WhisperKitExpoModule.startStreaming(config);
}

export async function stopStreaming(): Promise<{
  success: boolean;
  fullTranscription: string;
  segments: TranscriptionSegment[];
} | null> {
  const result = await WhisperKitExpoModule.stopStreaming();
  
  // Remove streaming listener
  if (eventEmitter) {
    eventEmitter.removeAllListeners('onStreamingUpdate');
  }
  
  return result;
}

export async function feedAudioData(audioData: ArrayBuffer): Promise<void> {
  // Convert ArrayBuffer to base64 for native bridge
  const base64 = btoa(String.fromCharCode(...new Uint8Array(audioData)));
  await WhisperKitExpoModule.feedAudioData(base64);
}

// Model management
export async function getAvailableModels(): Promise<AvailableModel[]> {
  return await WhisperKitExpoModule.getAvailableModels();
}

export async function downloadModel(
  modelName: string,
  onProgress?: DownloadListener
): Promise<boolean> {
  if (onProgress && eventEmitter) {
    eventEmitter.addListener('onModelDownloadProgress', onProgress);
  }
  
  return await WhisperKitExpoModule.downloadModel(modelName);
}

export function cancelModelDownload(): void {
  WhisperKitExpoModule.cancelModelDownload();
  
  // Remove download listener
  if (eventEmitter) {
    eventEmitter.removeAllListeners('onModelDownloadProgress');
  }
}

export async function deleteModel(modelName: string): Promise<boolean> {
  return await WhisperKitExpoModule.deleteModel(modelName);
}

// Language detection and support
export async function detectLanguage(file: string): Promise<LanguageDetectionResult | null> {
  const fileRegex = /^file:\/\//;
  const path = file.replace(fileRegex, "");
  return await WhisperKitExpoModule.detectLanguage(path);
}

export function getSupportedLanguages(): Record<string, string> {
  return WhisperKitExpoModule.getSupportedLanguages();
}

// Helper to check if transcriber is ready
export function isTranscriberReady(): boolean {
  return WhisperKitExpoModule.transcriberReady || false;
}

// Clean up all event listeners
export function cleanup(): void {
  if (eventEmitter) {
    eventEmitter.removeAllListeners();
  }
}

// Export components and types
export { TranscriberInitializer };
export * from './WhisperKitExpo.types';

// Default model configurations
export const ModelConfigurations = {
  tiny: {
    model: 'openai/whisper-tiny',
    computeUnits: 'cpuAndNeuralEngine' as const,
  },
  base: {
    model: 'openai/whisper-base', 
    computeUnits: 'cpuAndNeuralEngine' as const,
  },
  small: {
    model: 'openai/whisper-small',
    computeUnits: 'cpuAndNeuralEngine' as const,
  },
  medium: {
    model: 'openai/whisper-medium',
    computeUnits: 'all' as const,
  },
  large: {
    model: 'openai/whisper-large-v3',
    computeUnits: 'all' as const,
  },
  distilLarge: {
    model: 'distil-whisper/distil-large-v3',
    computeUnits: 'all' as const,
  }
};

// Default decoding options for common use cases
export const DecodingPresets = {
  accurate: {
    temperature: 0.0,
    compressionRatioThreshold: 2.4,
    logProbThreshold: -1.0,
    noSpeechThreshold: 0.6,
    wordTimestamps: true,
  } as DecodingOptions,
  
  fast: {
    temperature: 0.0,
    wordTimestamps: false,
    concurrentWorkerCount: 4,
  } as DecodingOptions,
  
  streaming: {
    temperature: 0.0,
    wordTimestamps: false,
    chunkingStrategy: 'vad' as const,
    sampleLength: 224,
  } as DecodingOptions,
};