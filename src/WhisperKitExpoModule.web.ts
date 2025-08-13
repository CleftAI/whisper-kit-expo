// Web stub for WhisperKitExpo module
export default {
  transcribe: async (path: string) => {
    throw new Error('WhisperKitExpo is not supported on web platform');
  },
  transcribeWithOptions: async (path: string, options: any) => {
    throw new Error('WhisperKitExpo is not supported on web platform');
  },
  loadTranscriber: async (options?: any) => {
    console.warn('WhisperKitExpo is not supported on web platform');
    return false;
  },
  startStreaming: async (config?: any) => {
    console.warn('WhisperKitExpo streaming is not supported on web platform');
    return false;
  },
  stopStreaming: async () => {
    return null;
  },
  feedAudioData: async (data: string) => {
    // No-op
  },
  getAvailableModels: async () => {
    return [];
  },
  downloadModel: async (modelName: string) => {
    console.warn('WhisperKitExpo model download is not supported on web platform');
    return false;
  },
  cancelModelDownload: () => {
    // No-op
  },
  deleteModel: async (modelName: string) => {
    return false;
  },
  detectLanguage: async (path: string) => {
    return null;
  },
  getSupportedLanguages: () => {
    return {};
  },
  transcriberReady: false,
};