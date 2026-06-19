import Foundation
import SwiftData

@Model
class TranslationStudyItem {
  var originalText: String = ""
  var translatedText: String = ""
  var translatedAt: Date = Date.now
  var application: String?
  var sourceLanguage: String = ""
  var targetLanguage: String = ""

  init(
    originalText: String,
    translatedText: String,
    translatedAt: Date = Date.now,
    application: String? = nil,
    sourceLanguage: String = "",
    targetLanguage: String = ""
  ) {
    self.originalText = originalText
    self.translatedText = translatedText
    self.translatedAt = translatedAt
    self.application = application
    self.sourceLanguage = sourceLanguage
    self.targetLanguage = targetLanguage
  }
}
