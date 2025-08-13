export type TranscribeResult = {
  success: boolean;
  value: string;
};

export type TranscriptionSegment = {
  id: number;
  seek: number;
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

export type WordTiming = {
  word: string;
  start: number;
  end: number;
  probability: number;
};

export type TranscriptionProgress = {
  progress: number; // 0.0 to 1.0
  currentTime: number;
  totalTime: number;
  text: string;
  segments: TranscriptionSegment[];
};

export type StreamingTranscriptionUpdate = {
  isPartial: boolean;
  text: string;
  segments: TranscriptionSegment[];
  currentTime: number;
};

export type DecodingOptions = {
  task?: 'transcribe' | 'translate';
  language?: string; // ISO 639-1 code, e.g., 'en', 'es', 'fr'
  temperature?: number;
  temperatureIncrementOnFallback?: number;
  temperatureFallbackCount?: number;
  sampleLength?: number;
  topK?: number;
  usePrefillPrompt?: boolean;
  usePrefillCache?: boolean;
  detectLanguage?: boolean;
  suppressBlank?: boolean;
  suppressTokens?: number[];
  withoutTimestamps?: boolean;
  wordTimestamps?: boolean;
  clipTimestamps?: [number, number];
  compressionRatioThreshold?: number;
  logProbThreshold?: number;
  noSpeechThreshold?: number;
  concurrentWorkerCount?: number;
  chunkingStrategy?: 'vad' | 'fixed';
};

export type ModelOptions = {
  model?: string; // e.g., 'openai/whisper-tiny', 'distil-whisper/distil-large-v3'
  downloadBase?: string;
  modelFolder?: string;
  modelRepo?: string;
  computeUnits?: 'cpuOnly' | 'cpuAndGPU' | 'cpuAndNeuralEngine' | 'all';
  prewarm?: boolean;
  load?: boolean;
};

export type AudioStreamConfig = {
  sampleRate?: number;
  numberOfChannels?: number;
  bufferDuration?: number; // in seconds
  vadOptions?: {
    silenceThreshold?: number;
    speechThreshold?: number;
    silenceDuration?: number;
    speechDuration?: number;
  };
};

export type TranscriptionOptions = DecodingOptions & {
  progressCallback?: (progress: TranscriptionProgress) => void;
  streamingCallback?: (update: StreamingTranscriptionUpdate) => void;
};

export type ModelDownloadProgress = {
  model: string;
  progress: number; // 0.0 to 1.0
  downloadedBytes: number;
  totalBytes: number;
  status: 'downloading' | 'completed' | 'failed';
  error?: string;
};

export type AvailableModel = {
  name: string;
  repo: string;
  size: number; // in bytes
  description: string;
  languages: string[];
  isDownloaded: boolean;
  isMultilingual: boolean;
};

export type LanguageDetectionResult = {
  detectedLanguage: string;
  languageProbabilities: Record<string, number>;
};
