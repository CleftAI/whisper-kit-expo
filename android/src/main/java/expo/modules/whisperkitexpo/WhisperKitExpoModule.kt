package expo.modules.whisperkitexpo

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

class TranscribeResult : Record {
  @Field
  var success: Boolean = false

  @Field
  var value: String = ""
}

class WhisperKitExpoModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("WhisperKitExpo")

    Property("transcriberReady") {
      false
    }

    AsyncFunction("loadTranscriber") {
      // WhisperKit is iOS-only, return false on Android
      false
    }

    AsyncFunction("transcribe") { path: String ->
      val result = TranscribeResult()
      result.success = false
      result.value = "WhisperKit is only available on iOS"
      result
    }
  }
}
