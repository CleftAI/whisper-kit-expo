// Web stub for WhisperKitExpo module
export default {
  transcribe: async (path: string) => {
    throw new Error('WhisperKitExpo is not supported on web platform');
  },
  loadTranscriber: async () => {
    console.warn('WhisperKitExpo is not supported on web platform');
    return false;
  },
  transcriberReady: false,
};