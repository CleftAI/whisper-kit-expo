import ExpoModulesCore
import WhisperKit
import Foundation
import AVFoundation

public class WhisperKitExpoModule: Module {
    var pipe: WhisperKit? = nil
    var initializing = false
    
    public func definition() -> ModuleDefinition {
        Name("WhisperKitExpo")
        
        Property("transcriberReady") {
            return pipe != nil
        }
        
        Events("onTranscriptionProgress", "onStreamingUpdate", "onModelDownloadProgress")
        
        // Simple model loading for backward compatibility
        AsyncFunction("loadTranscriber") { () -> Bool in
            initializing = true
            do {
                pipe = try await WhisperKit()
                return true
            } catch {
                print("Failed to load transcriber: \(error)")
                return false
            }
        }
        
        // Enhanced model loading with options
        AsyncFunction("loadTranscriberWithOptions") { (options: ModelOptions) -> Bool in
            initializing = true
            do {
                pipe = try await WhisperKit(
                    model: options.model,
                    downloadBase: options.downloadBase,
                    modelFolder: options.modelFolder,
                    download: true,
                    modelState: options.prewarm ?? true ? .prewarmed : .unloaded
                )
                return true
            } catch {
                print("Failed to load transcriber: \(error)")
                return false
            }
        }
        
        // Original simple transcribe function
        AsyncFunction("transcribe") { (path: String) -> TranscribeResult in
            guard initializing else {
                return TranscribeResult(success: false, value: "loadTranscriber() has not been called yet")
            }
            
            guard let whisperKit = pipe else {
                return TranscribeResult(success: false, value: "Model not loaded")
            }
            
            do {
                let results = try await whisperKit.transcribe(audioPath: path)
                let text = results.map { $0.text }.joined(separator: " ")
                return TranscribeResult(success: true, value: text)
            } catch {
                return TranscribeResult(success: false, value: error.localizedDescription)
            }
        }
        
        // Enhanced transcribe with options
        AsyncFunction("transcribeWithOptions") { (path: String, options: TranscriptionOptions?) -> TranscriptionResult in
            guard initializing else {
                return TranscriptionResult(
                    success: false,
                    text: "",
                    segments: [],
                    language: nil,
                    error: "loadTranscriber() has not been called yet"
                )
            }
            
            guard let whisperKit = pipe else {
                return TranscriptionResult(
                    success: false,
                    text: "",
                    segments: [],
                    language: nil,
                    error: "Model not loaded"
                )
            }
            
            do {
                let decodingOptions = options?.toDecodingOptions() ?? DecodingOptions()
                
                // Set up progress callback if needed
                var progressCallback: ((TranscriptionProgress) -> Void)? = nil
                if options?.progressCallback != nil {
                    progressCallback = { progress in
                        self.sendEvent("onTranscriptionProgress", [
                            "progress": progress.progress,
                            "currentTime": progress.currentTime,
                            "totalTime": progress.totalTime,
                            "text": progress.text,
                            "segments": progress.segments.map { $0.toDictionary() }
                        ])
                    }
                }
                
                let results = try await whisperKit.transcribe(
                    audioPath: path,
                    decodeOptions: decodingOptions,
                    callback: progressCallback
                )
                
                let allText = results.map { $0.text }.joined(separator: " ")
                let allSegments = results.flatMap { result in
                    result.segments.enumerated().map { index, segment in
                        TranscriptionSegment(
                            id: index,
                            seek: segment.seek,
                            start: segment.start,
                            end: segment.end,
                            text: segment.text,
                            tokens: segment.tokens,
                            temperature: Double(segment.temperature),
                            avgLogprob: Double(segment.avgLogprob),
                            compressionRatio: Double(segment.compressionRatio),
                            noSpeechProb: Double(segment.noSpeechProb),
                            words: segment.words?.map { WordTiming(from: $0) }
                        )
                    }
                }
                
                let detectedLanguage = results.first?.language
                
                return TranscriptionResult(
                    success: true,
                    text: allText,
                    segments: allSegments,
                    language: detectedLanguage,
                    error: nil
                )
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
        
        // Get available models
        AsyncFunction("getAvailableModels") { () -> [AvailableModel] in
            return WhisperModelUtils.getAvailableModels()
        }
        
        // Download specific model
        AsyncFunction("downloadModel") { (modelName: String) -> Bool in
            Task {
                do {
                    try await WhisperModelUtils.downloadModel(modelName: modelName) { progress in
                        self.sendEvent("onModelDownloadProgress", [
                            "model": progress.model,
                            "progress": progress.progress,
                            "downloadedBytes": progress.downloadedBytes,
                            "totalBytes": progress.totalBytes,
                            "status": progress.status
                        ])
                    }
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
        
        // Delete downloaded model
        AsyncFunction("deleteModel") { (modelName: String) -> Bool in
            return WhisperModelUtils.deleteModel(modelName: modelName)
        }
        
        // Detect language from audio
        AsyncFunction("detectLanguage") { (path: String) -> LanguageDetectionResult? in
            guard let whisperKit = pipe else {
                return nil
            }
            
            do {
                let audioFileURL = URL(fileURLWithPath: path)
                let audioSamples = try AudioProcessor.loadAudioSamples(from: audioFileURL)
                let languageProbs = try await whisperKit.detectLanguage(audioSamples: audioSamples)
                
                // Find the most likely language
                let detectedLang = languageProbs.max(by: { $0.value < $1.value })?.key ?? "en"
                
                return LanguageDetectionResult(
                    detectedLanguage: detectedLang,
                    languageProbabilities: languageProbs
                )
            } catch {
                print("Failed to detect language: \(error)")
                return nil
            }
        }
        
        // Get supported languages
        Function("getSupportedLanguages") { () -> [String: String] in
            return WhisperLanguages.supportedLanguages
        }
        
        // Placeholder streaming functions
        AsyncFunction("startStreaming") { (config: AudioStreamConfig?) -> Bool in
            // Streaming would require more complex implementation
            print("Streaming not yet implemented")
            return false
        }
        
        AsyncFunction("stopStreaming") { () -> StreamingResult? in
            return nil
        }
        
        AsyncFunction("feedAudioData") { (audioData: String) -> Void in
            // No-op for now
        }
        
        Function("cancelModelDownload") {
            // No-op for now
        }
    }
}

// MARK: - Model Management Utilities
struct WhisperModelUtils {
    static let availableModels: [AvailableModel] = [
        // Tiny models
        AvailableModel(
            name: "tiny.en",
            repo: "openai_whisper-tiny.en",
            size: 39_000_000,
            description: "Smallest model, English only",
            languages: ["en"],
            isMultilingual: false
        ),
        AvailableModel(
            name: "tiny",
            repo: "openai_whisper-tiny",
            size: 39_000_000,
            description: "Smallest multilingual model",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        
        // Base models
        AvailableModel(
            name: "base.en",
            repo: "openai_whisper-base.en",
            size: 74_000_000,
            description: "Fast English-only model",
            languages: ["en"],
            isMultilingual: false
        ),
        AvailableModel(
            name: "base",
            repo: "openai_whisper-base",
            size: 74_000_000,
            description: "Fast multilingual model",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        
        // Small models
        AvailableModel(
            name: "small.en",
            repo: "openai_whisper-small.en",
            size: 244_000_000,
            description: "Accurate English-only model",
            languages: ["en"],
            isMultilingual: false
        ),
        AvailableModel(
            name: "small",
            repo: "openai_whisper-small",
            size: 244_000_000,
            description: "Accurate multilingual model",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        
        // Medium models
        AvailableModel(
            name: "medium.en",
            repo: "openai_whisper-medium.en",
            size: 769_000_000,
            description: "High accuracy English-only",
            languages: ["en"],
            isMultilingual: false
        ),
        AvailableModel(
            name: "medium",
            repo: "openai_whisper-medium",
            size: 769_000_000,
            description: "High accuracy multilingual",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        
        // Large models
        AvailableModel(
            name: "large-v2",
            repo: "openai_whisper-large-v2",
            size: 1_550_000_000,
            description: "Previous large model version",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        AvailableModel(
            name: "large-v3",
            repo: "openai_whisper-large-v3",
            size: 1_550_000_000,
            description: "Latest and most accurate model",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        AvailableModel(
            name: "large-v3-turbo",
            repo: "openai_whisper-large-v3_turbo",
            size: 954_000_000,
            description: "Optimized large v3 for speed",
            languages: WhisperLanguages.supportedLanguages.keys.map { $0 },
            isMultilingual: true
        ),
        
        // Distil models
        AvailableModel(
            name: "distil-large-v3",
            repo: "distil-whisper_distil-large-v3",
            size: 756_000_000,
            description: "Distilled large model, faster",
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
        let modelVariant = getModelVariant(for: modelName)
        
        do {
            progressHandler(ModelDownloadProgress(
                model: modelName,
                progress: 0.1,
                downloadedBytes: 0,
                totalBytes: getModelSize(modelName),
                status: "downloading"
            ))
            
            // Initialize WhisperKit with the specific model - this triggers download
            let _ = try await WhisperKit(
                model: modelVariant,
                download: true,
                modelState: .unloaded
            )
            
            progressHandler(ModelDownloadProgress(
                model: modelName,
                progress: 1.0,
                downloadedBytes: getModelSize(modelName),
                totalBytes: getModelSize(modelName),
                status: "completed"
            ))
        } catch {
            throw error
        }
    }
    
    static func getModelVariant(for name: String) -> String {
        if name.contains("_") {
            return name
        }
        
        switch name {
        case "tiny.en": return "openai_whisper-tiny.en"
        case "tiny": return "openai_whisper-tiny"
        case "base.en": return "openai_whisper-base.en"
        case "base": return "openai_whisper-base"
        case "small.en": return "openai_whisper-small.en"
        case "small": return "openai_whisper-small"
        case "medium.en": return "openai_whisper-medium.en"
        case "medium": return "openai_whisper-medium"
        case "large-v2": return "openai_whisper-large-v2"
        case "large-v3": return "openai_whisper-large-v3"
        case "large-v3-turbo": return "openai_whisper-large-v3_turbo"
        case "distil-large-v3": return "distil-whisper_distil-large-v3"
        default: return "openai_whisper-base"
        }
    }
    
    static func getModelSize(_ name: String) -> Int64 {
        switch name {
        case "tiny.en", "tiny": return 39_000_000
        case "base.en", "base": return 74_000_000
        case "small.en", "small": return 244_000_000
        case "medium.en", "medium": return 769_000_000
        case "large-v2", "large-v3": return 1_550_000_000
        case "large-v3-turbo": return 954_000_000
        case "distil-large-v3": return 756_000_000
        default: return 74_000_000
        }
    }
    
    static func getModelFolder() -> String? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsPath?.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml").path
    }
    
    static func deleteModel(modelName: String) -> Bool {
        guard let modelFolder = getModelFolder() else { return false }
        
        let modelVariant = getModelVariant(for: modelName)
        let modelPath = (modelFolder as NSString).appendingPathComponent(modelVariant)
        
        do {
            if FileManager.default.fileExists(atPath: modelPath) {
                try FileManager.default.removeItem(atPath: modelPath)
                return true
            }
            return false
        } catch {
            print("Failed to delete model: \(error)")
            return false
        }
    }
    
    static func checkIfModelDownloaded(_ modelName: String) -> Bool {
        guard let modelFolder = getModelFolder() else { return false }
        
        let modelVariant = getModelVariant(for: modelName)
        let modelPath = (modelFolder as NSString).appendingPathComponent(modelVariant)
        
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: modelPath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let mlmodelcPath = (modelPath as NSString).appendingPathComponent("model.mlmodelc")
                return FileManager.default.fileExists(atPath: mlmodelcPath)
            }
        }
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

// MARK: - Type Definitions
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

struct WordTiming: Record {
    @Field var word: String = ""
    @Field var start: Double = 0
    @Field var end: Double = 0
    @Field var probability: Double = 0
    
    init() {}
    
    init(from word: WhisperKit.Word) {
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

struct TranscriptionProgress: Record {
    @Field var progress: Double = 0
    @Field var currentTime: Double = 0
    @Field var totalTime: Double = 0
    @Field var text: String = ""
    @Field var segments: [TranscriptionSegment] = []
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
    @Field var progressCallback: Bool? = nil
    
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
        if let withoutTimestamps = withoutTimestamps {
            options.withoutTimestamps = withoutTimestamps
        }
        if let compressionRatioThreshold = compressionRatioThreshold {
            options.compressionRatioThreshold = Float(compressionRatioThreshold)
        }
        if let logProbThreshold = logProbThreshold {
            options.logProbThreshold = Float(logProbThreshold)
        }
        if let noSpeechThreshold = noSpeechThreshold {
            options.noSpeechThreshold = Float(noSpeechThreshold)
        }
        
        return options
    }
}

struct AudioStreamConfig: Record {
    @Field var sampleRate: Int? = nil
    @Field var numberOfChannels: Int? = nil
    @Field var bufferDuration: Double? = nil
}

struct ModelDownloadProgress: Record {
    @Field var model: String = ""
    @Field var progress: Double = 0
    @Field var downloadedBytes: Int64 = 0
    @Field var totalBytes: Int64 = 0
    @Field var status: String = "downloading"
    @Field var error: String? = nil
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
}