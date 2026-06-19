import Foundation

@MainActor
enum TranslationStudyHistory {
  static func add(
    originalText: String,
    translatedText: String,
    application: String?,
    sourceLanguage: String,
    targetLanguage: String,
    translatedAt: Date = Date.now
  ) throws {
    let item = TranslationStudyItem(
      originalText: originalText,
      translatedText: translatedText,
      translatedAt: translatedAt,
      application: application,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage
    )

    Storage.shared.context.insert(item)
    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
  }

  static func delete(_ items: [TranslationStudyItem]) throws {
    for item in items {
      Storage.shared.context.delete(item)
    }

    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
  }

  static func deleteAll() throws {
    try Storage.shared.context.delete(model: TranslationStudyItem.self)
    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
  }
}
