import ExpoModulesCore
import WhisperKit
import Foundation
import AVFoundation

public class WhisperKitExpoModule: Module {
    var pipe: WhisperPipe? = nil
    var streamingPipe: StreamingWhisperPipe? = nil
    var initializing = false
    var downloadTask: Task<Void, Error>? = nil
    
    func getPipe() async throws -> WhisperPipe {
        while pipe == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return pipe!
    }
    
    public func definition() -> ModuleDefinition {
        Name("WhisperKitExpo")
        
        Property("transcriberReady") {
            return pipe != nil
        }
        
        Events("onTranscriptionProgress", "onStreamingUpdate", "onModelDownloadProgress")
        
        // Enhanced model loading with options
        AsyncFunction("loadTranscriber") { (options: ModelOptions?) -> Bool in
            initializing = true
            do {
                let modelOptions = options ?? ModelOptions()
                pipe = try await WhisperPipe(options: modelOptions)
                return true
            } catch {
                print("Failed to load transcriber: \(error)")
                return false
            }
        }
        
        // Original simple transcribe function for backward compatibility
        AsyncFunction("transcribe") { (path: String) -> TranscribeResult in
            if !initializing {
                return TranscribeResult(success: false, value: "loadTranscriber() has not been called yet")
            }
            
            do {
                let pipe = try await getPipe()
                let transcription = try await pipe.transcribe(path: path)
                return TranscribeResult(success: true, value: transcription)
            } catch {
                return TranscribeResult(success: false, value: error.localizedDescription)
            }
        }
        
        // Enhanced transcribe with options and callbacks
        AsyncFunction("transcribeWithOptions") { (path: String, options: TranscriptionOptions?) -> TranscriptionResult in
            if !initializing {
                return TranscriptionResult(
                    success: false,
                    text: "",
                    segments: [],
                    language: nil,
                    error: "loadTranscriber() has not been called yet"
                )
            }
            
            do {
                let pipe = try await getPipe()
                let result = try await pipe.transcribeWithOptions(
                    path: path,
                    options: options ?? TranscriptionOptions(),
                    progressHandler: { progress in
                        self.sendEvent("onTranscriptionProgress", progress.toDictionary())
                    }
                )
                return result
            } catch {
                return TranscriptionResult(
                    success: false,
                    text: "",
                    segments: [],
                    language: nil,
                    error: error.localizedDescription
                )
            }
        }
        
        // Start streaming transcription
        AsyncFunction("startStreaming") { (config: AudioStreamConfig?) -> Bool in
            if !initializing {
                return false
            }
            
            do {
                streamingPipe = try await StreamingWhisperPipe(
                    whisperPipe: try await getPipe(),
                    config: config ?? AudioStreamConfig()
                )
                
                streamingPipe?.onUpdate = { update in
                    self.sendEvent("onStreamingUpdate", update.toDictionary())
                }
                
                try await streamingPipe?.start()
                return true
            } catch {
                print("Failed to start streaming: \(error)")
                return false
            }
        }
        
        // Stop streaming transcription
        AsyncFunction("stopStreaming") { () -> StreamingResult? in
            guard let streaming = streamingPipe else {
                return nil
            }
            
            let result = await streaming.stop()
            streamingPipe = nil
            return result
        }
        
        // Feed audio data to streaming transcription
        AsyncFunction("feedAudioData") { (audioData: Data) -> Void in
            guard let streaming = streamingPipe else {
                return
            }
            
            await streaming.feedAudioData(audioData)
        }
        
        // Get available models
        AsyncFunction("getAvailableModels") { () -> [AvailableModel] in
            return WhisperModelUtils.getAvailableModels()
        }
        
        // Download specific model
        AsyncFunction("downloadModel") { (modelName: String) -> Bool in
            downloadTask = Task {
                do {
                    try await WhisperModelUtils.downloadModel(
                        modelName: modelName,
                        progressHandler: { progress in
                            self.sendEvent("onModelDownloadProgress", progress.toDictionary())
                        }
                    )
                } catch {
                    self.sendEvent("onModelDownloadProgress", [
                        "model": modelName,
                        "progress": 0.0,
                        "status": "failed",
                        "error": error.localizedDescription
                    ])
                }
            }
            return true
        }
        
        // Cancel model download
        Function("cancelModelDownload") {
            downloadTask?.cancel()
            downloadTask = nil
        }
        
        // Delete downloaded model
        AsyncFunction("deleteModel") { (modelName: String) -> Bool in
            return WhisperModelUtils.deleteModel(modelName: modelName)
        }
        
        // Detect language from audio
        AsyncFunction("detectLanguage") { (path: String) -> LanguageDetectionResult? in
            if !initializing {
                return nil
            }
            
            do {
                let pipe = try await getPipe()
                return try await pipe.detectLanguage(path: path)
            } catch {
                print("Failed to detect language: \(error)")
                return nil
            }
        }
        
        // Get supported languages
        Function("getSupportedLanguages") { () -> [String: String] in
            return WhisperLanguages.supportedLanguages
        }
    }
}

// MARK: - WhisperPipe Actor
actor WhisperPipe {
    private var pipe: WhisperKit
    private var modelOptions: ModelOptions
    
    init(options: ModelOptions) async throws {
        self.modelOptions = options
        
        let config = WhisperKitConfig(
            model: options.model,
            downloadBase: options.downloadBase,
            modelRepo: options.modelRepo ?? "argmaxinc/WhisperKit",
            modelFolder: options.modelFolder,
            computeUnits: options.computeUnits?.toWhisperComputeUnits() ?? .all,
            prewarm: options.prewarm ?? true,
            load: options.load ?? true
        )
        
        self.pipe = try await WhisperKit(config: config)
    }
    
    func transcribe(path: String) async throws -> String {
        let results = try await self.pipe.transcribe(audioPath: path)
        return results.first?.text ?? ""
    }
    
    func transcribeWithOptions(
        path: String,
        options: TranscriptionOptions,
        progressHandler: @escaping (TranscriptionProgress) -> Void
    ) async throws -> TranscriptionResult {
        let decodingOptions = options.toDecodingOptions()
        
        let results = try await self.pipe.transcribe(
            audioPath: path,
            decodeOptions: decodingOptions,
            callback: { progress in
                progressHandler(TranscriptionProgress(from: progress))
            }
        )
        
        guard let result = results.first else {
            throw WhisperError.transcriptionFailed
        }
        
        return TranscriptionResult(from: result)
    }
    
    func detectLanguage(path: String) async throws -> LanguageDetectionResult {
        let detection = try await self.pipe.detectLanguage(audioPath: path)
        return LanguageDetectionResult(from: detection)
    }
}

// MARK: - Streaming Transcription
actor StreamingWhisperPipe {
    private var whisperPipe: WhisperPipe
    private var audioEngine: AVAudioEngine
    private var audioBuffer: AVAudioPCMBuffer
    private var isStreaming: Bool = false
    private var config: AudioStreamConfig
    private var streamingTask: Task<Void, Never>?
    
    var onUpdate: ((StreamingTranscriptionUpdate) -> Void)?
    
    init(whisperPipe: WhisperPipe, config: AudioStreamConfig) async throws {
        self.whisperPipe = whisperPipe
        self.config = config
        self.audioEngine = AVAudioEngine()
        
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(config.sampleRate ?? 16000),
            channels: UInt32(config.numberOfChannels ?? 1)
        )!
        
        let frameCapacity = UInt32((config.bufferDuration ?? 1.0) * Double(config.sampleRate ?? 16000))
        self.audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)!
    }
    
    func start() async throws {
        guard !isStreaming else { return }
        
        isStreaming = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            Task {
                await self.processAudioBuffer(buffer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        streamingTask = Task {
            await startStreamingLoop()
        }
    }
    
    func stop() async -> StreamingResult {
        isStreaming = false
        streamingTask?.cancel()
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Process any remaining audio
        let finalResult = await processFinalAudio()
        
        return StreamingResult(
            success: true,
            fullTranscription: finalResult.text,
            segments: finalResult.segments
        )
    }
    
    func feedAudioData(_ data: Data) async {
        // Convert data to audio buffer and process
        guard let buffer = data.toAudioBuffer(format: audioBuffer.format) else { return }
        await processAudioBuffer(buffer)
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        // Add buffer to our accumulating buffer
        // When we have enough audio, process it
        // This is a simplified implementation
    }
    
    private func startStreamingLoop() async {
        while isStreaming {
            // Process accumulated audio periodically
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            if audioBuffer.frameLength > 0 {
                // Process the audio
                let update = await processStreamingAudio()
                onUpdate?(update)
            }
        }
    }
    
    private func processStreamingAudio() async -> StreamingTranscriptionUpdate {
        // This is a simplified implementation
        // In reality, you'd process the audio buffer through WhisperKit
        return StreamingTranscriptionUpdate(
            isPartial: true,
            text: "",
            segments: [],
            currentTime: 0
        )
    }
    
    private func processFinalAudio() async -> (text: String, segments: [TranscriptionSegment]) {
        // Process any remaining audio in the buffer
        return (text: "", segments: [])
    }
}

// MARK: - Model Management Utilities
struct WhisperModelUtils {
    static let availableModels: [AvailableModel] = [
        AvailableModel(
            name: "tiny",
            repo: "openai/whisper-tiny",
            size: 39_000_000,
            description: "Smallest and fastest model",
            languages: ["en"],
            isMultilingual: false
        ),
        AvailableModel(
            name: "base",
            repo: "openai/whisper-base",
            size: 74_000_000,
            description: "Good balance of speed and accuracy",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        AvailableModel(
            name: "small",
            repo: "openai/whisper-small",
            size: 244_000_000,
            description: "More accurate than base",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        AvailableModel(
            name: "medium",
            repo: "openai/whisper-medium",
            size: 769_000_000,
            description: "Good accuracy, slower",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        AvailableModel(
            name: "large-v3",
            repo: "openai/whisper-large-v3",
            size: 1_550_000_000,
            description: "Most accurate, slowest",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        AvailableModel(
            name: "distil-large-v3",
            repo: "distil-whisper/distil-large-v3",
            size: 756_000_000,
            description: "Faster than large-v3, similar accuracy",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        )
    ]
    
    static func getAvailableModels() -> [AvailableModel] {
        return availableModels.map { model in
            var mutableModel = model
            mutableModel.isDownloaded = checkIfModelDownloaded(model.name)
            return mutableModel
        }
    }
    
    static func downloadModel(
        modelName: String,
        progressHandler: @escaping (ModelDownloadProgress) -> Void
    ) async throws {
        // Implementation would use WhisperKit's download functionality
        // This is a placeholder
        progressHandler(ModelDownloadProgress(
            model: modelName,
            progress: 0.0,
            downloadedBytes: 0,
            totalBytes: 0,
            status: .downloading
        ))
    }
    
    static func deleteModel(modelName: String) -> Bool {
        // Delete model from local storage
        return true
    }
    
    static func checkIfModelDownloaded(_ modelName: String) -> Bool {
        // Check if model exists in local storage
        return false
    }
}

// MARK: - Language Support
struct WhisperLanguages {
    static let supportedLanguages: [String: String] = [
        "en": "English",
        "zh": "Chinese",
        "de": "German",
        "es": "Spanish",
        "ru": "Russian",
        "ko": "Korean",
        "fr": "French",
        "ja": "Japanese",
        "pt": "Portuguese",
        "tr": "Turkish",
        "pl": "Polish",
        "ca": "Catalan",
        "nl": "Dutch",
        "ar": "Arabic",
        "sv": "Swedish",
        "it": "Italian",
        "id": "Indonesian",
        "hi": "Hindi",
        "fi": "Finnish",
        "vi": "Vietnamese",
        "he": "Hebrew",
        "uk": "Ukrainian",
        "el": "Greek",
        "ms": "Malay",
        "cs": "Czech",
        "ro": "Romanian",
        "da": "Danish",
        "hu": "Hungarian",
        "ta": "Tamil",
        "no": "Norwegian",
        "th": "Thai"
    ]
}

// MARK: - Type Definitions and Extensions
struct TranscribeResult: Record {
    @Field var success: Bool = false
    @Field var value: String = ""
}

struct TranscriptionResult: Record {
    @Field var success: Bool = true
    @Field var text: String = ""
    @Field var segments: [TranscriptionSegment] = []
    @Field var language: String? = nil
    @Field var error: String? = nil
}

struct TranscriptionSegment: Record {
    @Field var id: Int = 0
    @Field var seek: Int = 0
    @Field var start: Double = 0
    @Field var end: Double = 0
    @Field var text: String = ""
    @Field var tokens: [Int] = []
    @Field var temperature: Double = 0
    @Field var avgLogprob: Double = 0
    @Field var compressionRatio: Double = 0
    @Field var noSpeechProb: Double = 0
    @Field var words: [WordTiming]? = nil
}

struct WordTiming: Record {
    @Field var word: String = ""
    @Field var start: Double = 0
    @Field var end: Double = 0
    @Field var probability: Double = 0
}

struct TranscriptionProgress: Record {
    @Field var progress: Double = 0
    @Field var currentTime: Double = 0
    @Field var totalTime: Double = 0
    @Field var text: String = ""
    @Field var segments: [TranscriptionSegment] = []
    
    init(from whisperProgress: WhisperKit.TranscriptionProgress) {
        // Convert WhisperKit progress to our format
        self.progress = whisperProgress.progress
        self.currentTime = whisperProgress.currentTime
        self.totalTime = whisperProgress.totalTime
        self.text = whisperProgress.text
        self.segments = whisperProgress.segments.map { TranscriptionSegment(from: $0) }
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "progress": progress,
            "currentTime": currentTime,
            "totalTime": totalTime,
            "text": text,
            "segments": segments.map { $0.toDictionary() }
        ]
    }
}

struct StreamingTranscriptionUpdate: Record {
    @Field var isPartial: Bool = true
    @Field var text: String = ""
    @Field var segments: [TranscriptionSegment] = []
    @Field var currentTime: Double = 0
    
    func toDictionary() -> [String: Any] {
        return [
            "isPartial": isPartial,
            "text": text,
            "segments": segments.map { $0.toDictionary() },
            "currentTime": currentTime
        ]
    }
}

struct StreamingResult: Record {
    @Field var success: Bool = true
    @Field var fullTranscription: String = ""
    @Field var segments: [TranscriptionSegment] = []
}

struct ModelOptions: Record {
    @Field var model: String? = nil
    @Field var downloadBase: String? = nil
    @Field var modelFolder: String? = nil
    @Field var modelRepo: String? = nil
    @Field var computeUnits: String? = nil
    @Field var prewarm: Bool? = nil
    @Field var load: Bool? = nil
}

struct TranscriptionOptions: Record {
    @Field var task: String? = nil
    @Field var language: String? = nil
    @Field var temperature: Double? = nil
    @Field var temperatureIncrementOnFallback: Double? = nil
    @Field var temperatureFallbackCount: Int? = nil
    @Field var sampleLength: Int? = nil
    @Field var topK: Int? = nil
    @Field var usePrefillPrompt: Bool? = nil
    @Field var usePrefillCache: Bool? = nil
    @Field var detectLanguage: Bool? = nil
    @Field var suppressBlank: Bool? = nil
    @Field var suppressTokens: [Int]? = nil
    @Field var withoutTimestamps: Bool? = nil
    @Field var wordTimestamps: Bool? = nil
    @Field var clipTimestamps: [Double]? = nil
    @Field var compressionRatioThreshold: Double? = nil
    @Field var logProbThreshold: Double? = nil
    @Field var noSpeechThreshold: Double? = nil
    @Field var concurrentWorkerCount: Int? = nil
    @Field var chunkingStrategy: String? = nil
    
    func toDecodingOptions() -> DecodingOptions {
        var options = DecodingOptions()
        
        if let task = task {
            options.task = task == "translate" ? .translate : .transcribe
        }
        if let language = language {
            options.language = language
        }
        if let temperature = temperature {
            options.temperature = Float(temperature)
        }
        if let wordTimestamps = wordTimestamps {
            options.wordTimestamps = wordTimestamps
        }
        // ... map other options
        
        return options
    }
}

struct AudioStreamConfig: Record {
    @Field var sampleRate: Int? = nil
    @Field var numberOfChannels: Int? = nil
    @Field var bufferDuration: Double? = nil
    // VAD options would be nested here
}

struct ModelDownloadProgress: Record {
    @Field var model: String = ""
    @Field var progress: Double = 0
    @Field var downloadedBytes: Int64 = 0
    @Field var totalBytes: Int64 = 0
    @Field var status: String = "downloading"
    @Field var error: String? = nil
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "model": model,
            "progress": progress,
            "downloadedBytes": downloadedBytes,
            "totalBytes": totalBytes,
            "status": status
        ]
        if let error = error {
            dict["error"] = error
        }
        return dict
    }
}

struct AvailableModel: Record {
    @Field var name: String = ""
    @Field var repo: String = ""
    @Field var size: Int64 = 0
    @Field var description: String = ""
    @Field var languages: [String] = []
    @Field var isDownloaded: Bool = false
    @Field var isMultilingual: Bool = false
}

struct LanguageDetectionResult: Record {
    @Field var detectedLanguage: String = ""
    @Field var languageProbabilities: [String: Double] = [:]
    
    init(from detection: WhisperKit.LanguageDetection) {
        self.detectedLanguage = detection.language
        self.languageProbabilities = detection.probabilities
    }
}

// MARK: - Helper Extensions
extension String {
    func toWhisperComputeUnits() -> WhisperKit.ComputeUnits {
        switch self {
        case "cpuOnly": return .cpuOnly
        case "cpuAndGPU": return .cpuAndGPU
        case "cpuAndNeuralEngine": return .cpuAndNeuralEngine
        default: return .all
        }
    }
}

extension Data {
    func toAudioBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Convert Data to AVAudioPCMBuffer
        // Implementation would go here
        return nil
    }
}

extension TranscriptionSegment {
    init(from segment: WhisperKit.TranscriptionSegment) {
        self.id = segment.id
        self.seek = segment.seek
        self.start = segment.start
        self.end = segment.end
        self.text = segment.text
        self.tokens = segment.tokens
        self.temperature = Double(segment.temperature)
        self.avgLogprob = Double(segment.avgLogprob)
        self.compressionRatio = Double(segment.compressionRatio)
        self.noSpeechProb = Double(segment.noSpeechProb)
        
        if let words = segment.words {
            self.words = words.map { WordTiming(from: $0) }
        }
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "seek": seek,
            "start": start,
            "end": end,
            "text": text,
            "tokens": tokens,
            "temperature": temperature,
            "avgLogprob": avgLogprob,
            "compressionRatio": compressionRatio,
            "noSpeechProb": noSpeechProb
        ]
        
        if let words = words {
            dict["words"] = words.map { $0.toDictionary() }
        }
        
        return dict
    }
}

extension WordTiming {
    init(from word: WhisperKit.WordTiming) {
        self.word = word.word
        self.start = word.start
        self.end = word.end
        self.probability = Double(word.probability)
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "word": word,
            "start": start,
            "end": end,
            "probability": probability
        ]
    }
}

extension TranscriptionResult {
    init(from result: WhisperKit.TranscriptionResult) {
        self.success = true
        self.text = result.text
        self.segments = result.segments.map { TranscriptionSegment(from: $0) }
        self.language = result.language
        self.error = nil
    }
}

// MARK: - Error Types
enum WhisperError: Error {
    case transcriptionFailed
    case modelNotLoaded
    case invalidAudioFormat
    case streamingNotActive
}