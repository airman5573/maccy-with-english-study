import AppKit
import Defaults
import Foundation
import Logging
import NaturalLanguage

final class DeepSeekTranslator {
  static let shared = DeepSeekTranslator()

  private static let minimumStudyTextLength = 15
  private static let maximumStudyTextLength = 3000
  private static let minimumLanguageConfidence = 0.25
  private static let minimumNaturalLanguageScore = 3

  private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
  private let logger = Logger(label: "org.p0deje.Maccy.DeepSeekTranslator")
  private let logNamespace = "maccy.translation"
  private let logScenario = "copy-translate"

  private init() {}

  func translateIfNeeded(_ item: HistoryItem, copiedFromMaccy: Bool = false) {
    let requestId = "maccy-\(UUID().uuidString)"

    guard Defaults[.translationEnabled] else { return }
    guard !copiedFromMaccy else {
      webmateLog(
        "translation skipped: item copied from Maccy",
        requestId: requestId,
        context: [
          "reason": "fromMaccy",
          "copied_from_maccy": copiedFromMaccy
        ]
      )
      return
    }
    guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      webmateLog(
        "translation skipped: no plain text",
        requestId: requestId,
        context: ["reason": "empty_or_non_text"]
      )
      return
    }
    let hasFileURLs = !item.fileURLs.isEmpty
    guard !hasFileURLs, !Self.isOnlyFilePathText(text) else {
      webmateLog(
        "translation skipped: file path",
        requestId: requestId,
        context: [
          "reason": "file_path",
          "has_file_urls": hasFileURLs,
          "text_length": text.count
        ]
      )
      return
    }
    let candidateDecision = Self.translationCandidateDecision(for: text)
    guard candidateDecision.shouldTranslate else {
      webmateLog(
        "translation skipped: not study candidate",
        requestId: requestId,
        context: candidateDecision.context
      )
      return
    }
    guard let direction = TranslationDirection.detect(text) else {
      webmateLog(
        "translation skipped: unsupported language",
        requestId: requestId,
        context: ["text_length": text.count]
      )
      return
    }

    let apiKey = DeepSeekAPIKeyStore.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
      webmateLog(
        "translation skipped: missing API key",
        level: "warn",
        requestId: requestId,
        context: ["text_length": text.count, "target": direction.targetName]
      )
      return
    }

    let model = Defaults[.translationModel].trimmingCharacters(in: .whitespacesAndNewlines)
    let application = item.application
    let firstCopiedAt = item.firstCopiedAt
    let lastCopiedAt = item.lastCopiedAt
    var queueContext: [String: Any] = [
      "source": direction.sourceName,
      "target": direction.targetName,
      "text_length": text.count,
      "model": model.isEmpty ? "deepseek-v4-flash" : model,
      "source_application": application ?? ""
    ]
    if let score = candidateDecision.naturalLanguageScore {
      queueContext["natural_language_score"] = score
    }
    if let language = candidateDecision.language {
      queueContext["recognized_language"] = language
    }
    if let confidence = candidateDecision.languageConfidence {
      queueContext["recognized_language_confidence"] = confidence
    }

    webmateLog(
      "translation queued",
      requestId: requestId,
      context: queueContext
    )

    Task { [apiKey, model, text, direction, application, firstCopiedAt, lastCopiedAt, requestId] in
      do {
        let translatedText = try await requestTranslation(
          text,
          direction: direction,
          apiKey: apiKey,
          model: model.isEmpty ? "deepseek-v4-flash" : model,
          requestId: requestId
        )

        await addTranslation(
          translatedText,
          originalText: text,
          application: application,
          sourceLanguage: direction.sourceName,
          targetLanguage: direction.targetName,
          firstCopiedAt: firstCopiedAt,
          lastCopiedAt: lastCopiedAt,
          requestId: requestId
        )
      } catch {
        webmateLog(
          "translation failed",
          level: "error",
          requestId: requestId,
          context: ["error": error.localizedDescription]
        )
        logger.error("DeepSeek translation failed: \(error.localizedDescription)")
      }
    }
  }

  private func requestTranslation(
    _ text: String,
    direction: TranslationDirection,
    apiKey: String,
    model: String,
    requestId: String
  ) async throws -> String {
    webmateLog(
      "DeepSeek request starting",
      requestId: requestId,
      context: ["model": model, "source": direction.sourceName, "target": direction.targetName]
    )

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
      model: model,
      messages: [
        ChatMessage(
          role: "system",
          content: """
          You are a precise English-Korean translator. Translate only between English and Korean. Return only the translated text, with no explanation, quotes, labels, markdown fences, or alternatives. Preserve meaning, tone, paragraph breaks, Markdown structure, URLs, file paths, code identifiers, and numbers. Do not translate proper nouns unless there is a widely-used natural translation.
          """
        ),
        ChatMessage(
          role: "user",
          content: """
          Translate the following \(direction.sourceName) text into \(direction.targetName). Return only the translation.

          \(text)
          """
        )
      ],
      temperature: 0.2,
      thinking: ThinkingMode(type: "disabled")
    ))

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw TranslationError.invalidResponse
    }

    webmateLog(
      "DeepSeek response received",
      level: 200..<300 ~= httpResponse.statusCode ? "info" : "warn",
      requestId: requestId,
      context: ["status_code": httpResponse.statusCode, "response_bytes": data.count]
    )

    guard 200..<300 ~= httpResponse.statusCode else {
      throw TranslationError.requestFailed(
        statusCode: httpResponse.statusCode,
        message: String(data: data, encoding: .utf8) ?? ""
      )
    }

    let responseBody = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    guard let content = responseBody.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
          !content.isEmpty else {
      throw TranslationError.emptyTranslation
    }

    webmateLog(
      "DeepSeek translation decoded",
      requestId: requestId,
      context: ["translation_length": content.count]
    )

    return content
  }

  @MainActor
  private func addTranslation(
    _ translatedText: String,
    originalText: String,
    application: String?,
    sourceLanguage: String,
    targetLanguage: String,
    firstCopiedAt: Date,
    lastCopiedAt: Date,
    requestId: String
  ) {
    let trimmedTranslation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTranslation.isEmpty else {
      webmateLog(
        "translation skipped: empty trimmed output",
        requestId: requestId,
        context: ["original_length": originalText.count]
      )
      return
    }
    guard trimmedTranslation != originalText else {
      webmateLog(
        "translation skipped: unchanged output",
        requestId: requestId,
        context: ["original_length": originalText.count]
      )
      return
    }
    guard let data = trimmedTranslation.data(using: .utf8) else {
      webmateLog(
        "translation skipped: output encoding failed",
        level: "warn",
        requestId: requestId,
        context: ["translation_length": trimmedTranslation.count]
      )
      return
    }

    do {
      try TranslationStudyHistory.add(
        originalText: originalText,
        translatedText: trimmedTranslation,
        application: application,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage
      )
      webmateLog("translation study item added", requestId: requestId)
    } catch {
      webmateLog(
        "translation study item failed",
        level: "warn",
        requestId: requestId,
        context: ["error": error.localizedDescription]
      )
    }

    webmateLog(
      "adding translation history item",
      requestId: requestId,
      context: [
        "original_length": originalText.count,
        "translation_length": trimmedTranslation.count,
        "macos_15_or_newer": ProcessInfo.processInfo.isOperatingSystemAtLeast(
          OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
      ]
    )

    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: data)
    let item = HistoryItem()

    // On macOS 14, SwiftData-backed relationship properties can trap if the model is
    // accessed before being inserted into a ModelContext. Insert first, then attach
    // contents and generate the preview title.
    if #unavailable(macOS 15.0) {
      try? History.shared.insertIntoStorage(item)
      webmateLog("inserted empty translation item before attaching contents", requestId: requestId)
    }

    item.contents = [content]
    item.application = application

    // Keep the translation immediately after the original item in default chronological sorts,
    // without writing the translation back to the system clipboard.
    item.firstCopiedAt = firstCopiedAt.addingTimeInterval(-0.001)
    item.lastCopiedAt = lastCopiedAt.addingTimeInterval(-0.001)
    item.title = item.generateTitle()

    History.shared.add(item, notify: false, trackSession: false)
    webmateLog("translation history item added", requestId: requestId)
  }

  private func webmateLog(
    _ message: String,
    level: String = "info",
    requestId: String,
    context: [String: Any]? = nil
  ) {
    WebmateLog.send(
      namespace: logNamespace,
      scenario: logScenario,
      level: level,
      message: message,
      context: context,
      requestId: requestId
    )
  }

  private static func translationCandidateDecision(for text: String) -> TranslationCandidateDecision {
    let textLength = text.count

    if textLength < minimumStudyTextLength {
      return .skip(
        reason: "too_short",
        context: [
          "text_length": textLength,
          "minimum_length": minimumStudyTextLength
        ]
      )
    }

    if textLength > maximumStudyTextLength {
      return .skip(
        reason: "too_long",
        context: [
          "text_length": textLength,
          "maximum_length": maximumStudyTextLength
        ]
      )
    }

    if isURLLike(text) {
      return .skip(reason: "url_like", context: ["text_length": textLength])
    }

    if isEmailLike(text) {
      return .skip(reason: "email_like", context: ["text_length": textLength])
    }

    if looksLikeCode(text) {
      return .skip(reason: "code_like", context: ["text_length": textLength])
    }

    guard let languageCandidate = englishOrKoreanLanguageCandidate(for: text) else {
      return .skip(
        reason: "unsupported_natural_language",
        context: [
          "text_length": textLength,
          "minimum_language_confidence": minimumLanguageConfidence
        ]
      )
    }

    let features = NaturalLanguageFeatures(text)
    let score = naturalLanguageScore(features)
    guard score >= minimumNaturalLanguageScore else {
      return .skip(
        reason: "low_natural_language_score",
        language: languageCandidate.language.rawValue,
        languageConfidence: languageCandidate.confidence,
        naturalLanguageScore: score,
        context: features.logContext(
          textLength: textLength,
          reason: "low_natural_language_score",
          minimumScore: minimumNaturalLanguageScore,
          language: languageCandidate.language.rawValue,
          languageConfidence: languageCandidate.confidence,
          score: score
        )
      )
    }

    return .allow(
      language: languageCandidate.language.rawValue,
      languageConfidence: languageCandidate.confidence,
      naturalLanguageScore: score,
      context: [
        "text_length": textLength,
        "natural_language_score": score,
        "recognized_language": languageCandidate.language.rawValue,
        "recognized_language_confidence": languageCandidate.confidence
      ]
    )
  }

  private static func englishOrKoreanLanguageCandidate(for text: String) -> LanguageCandidate? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)

    let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
    let englishConfidence = hypotheses[.english] ?? 0
    let koreanConfidence = hypotheses[.korean] ?? 0

    let candidate = englishConfidence >= koreanConfidence
      ? LanguageCandidate(language: .english, confidence: englishConfidence)
      : LanguageCandidate(language: .korean, confidence: koreanConfidence)

    guard candidate.confidence >= minimumLanguageConfidence else {
      return nil
    }

    return candidate
  }

  private static func naturalLanguageScore(_ features: NaturalLanguageFeatures) -> Int {
    var score = 0

    if features.letterRatio >= 0.60 {
      score += 2
    } else if features.letterRatio >= 0.45 {
      score += 1
    }

    if features.englishWordCount >= 4 {
      score += 2
    } else if features.englishWordCount >= 3 && features.hasSentencePunctuation {
      score += 1
    }

    if features.hangulCount >= 10 {
      score += 2
    } else if features.hangulCount >= 8 && features.hasSentencePunctuation {
      score += 1
    }

    if features.hasSentencePunctuation {
      score += 1
    }

    if features.hasCommonEnglishFunctionWord {
      score += 1
    }

    if features.hasKoreanSentenceEnding {
      score += 1
    }

    if features.digitRatio > 0.30 {
      score -= 2
    }

    if features.codeSymbolRatio > 0.12 {
      score -= 2
    }

    if features.hasVeryLongSingleToken {
      score -= 1
    }

    return score
  }

  private static func isURLLike(_ text: String) -> Bool {
    if matches(#"\b(?:https?|ftp)://\S+"#, text, options: [.regularExpression, .caseInsensitive]) ||
      matches(#"\bwww\.\S+"#, text, options: [.regularExpression, .caseInsensitive]) ||
      matches(#"\bmailto:"#, text, options: [.regularExpression, .caseInsensitive]) {
      return true
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
      return false
    }

    return matches(
      #"^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}(?:[/#?][^\s]*)?$"#,
      trimmed,
      options: [.regularExpression, .caseInsensitive]
    )
  }

  private static func isEmailLike(_ text: String) -> Bool {
    matches(
      #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
      text,
      options: [.regularExpression, .caseInsensitive]
    )
  }

  private static func looksLikeCode(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
      (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
      return true
    }

    if matches(#"</?[A-Za-z][^>]*>"#, trimmed) {
      return true
    }

    let codePatterns = [
      #"(?m)^\s*(let|var|const|func|class|struct|enum|import|return|if|for|while|switch|guard|case|extension|protocol)\b"#,
      #"(?m)^\s*(npm|pnpm|yarn|git|cd|ls|mkdir|rm|cp|mv|curl|ssh|sudo|xcodebuild)\b"#,
      #"=>|->|==|!=|<=|>="#,
      #"[A-Za-z_][A-Za-z0-9_]*\s*\([^)]*\)"#,
      #"(?m)^\s*[}\])];,]+\s*$"#
    ]

    let matchedCount = codePatterns.filter { matches($0, trimmed) }.count
    if matchedCount >= 2 {
      return true
    }

    let features = NaturalLanguageFeatures(trimmed)
    if hasIndentedCodeBlock(trimmed, features: features) {
      return true
    }

    if features.codeSymbolRatio > 0.18 && features.letterRatio < 0.75 {
      return true
    }

    let hasWhitespace = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    if !hasWhitespace && trimmed.count >= 6 {
      if matches(#"^[A-Za-z]+[A-Z][A-Za-z0-9]*$"#, trimmed) ||
        matches(#"^[A-Za-z0-9]+([_-][A-Za-z0-9]+)+$"#, trimmed) ||
        matches(#"^[A-Z0-9_]{6,}$"#, trimmed) {
        return true
      }
    }

    return false
  }

  private static func hasIndentedCodeBlock(
    _ text: String,
    features: NaturalLanguageFeatures
  ) -> Bool {
    guard text.contains("\n") else {
      return false
    }

    let lines = text
      .components(separatedBy: .newlines)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let indentedLines = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }

    guard lines.count >= 2,
          Double(indentedLines.count) / Double(lines.count) >= 0.5 else {
      return false
    }

    // Wrapped prose copied from web views, terminals, and chat UIs often carries
    // two-space continuation indentation. Do not treat indentation alone as code
    // when the text already has strong English/Korean natural-language signals.
    return !hasStrongNaturalLanguageSignals(features)
  }

  private static func hasStrongNaturalLanguageSignals(_ features: NaturalLanguageFeatures) -> Bool {
    naturalLanguageScore(features) >= minimumNaturalLanguageScore &&
      (
        features.hangulCount >= 10 ||
        features.hasSentencePunctuation ||
        features.hasCommonEnglishFunctionWord ||
        features.hasKoreanSentenceEnding
      )
  }

  private static func isOnlyFilePathText(_ text: String) -> Bool {
    let lines = text
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard !lines.isEmpty else { return false }
    return lines.allSatisfy(isFilePathLike)
  }

  private static func isFilePathLike(_ text: String) -> Bool {
    let quotedText = unquote(text.trimmingCharacters(in: .whitespacesAndNewlines))
    let text = quotedText.text

    guard !text.isEmpty else { return false }
    guard quotedText.wasQuoted || !hasUnescapedWhitespace(text) else {
      return false
    }

    if text.lowercased().hasPrefix("file://") {
      return true
    }

    if text.hasPrefix("/") ||
      text.hasPrefix("~/") ||
      text.hasPrefix("./") ||
      text.hasPrefix("../") ||
      text.hasPrefix("\\\\") ||
      text.hasPrefix(".\\") ||
      text.hasPrefix("..\\") {
      return true
    }

    if matches(#"^[A-Za-z]:[\\/].+"#, text) {
      return true
    }

    guard text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
      return false
    }

    if text.contains("/") || text.contains("\\") {
      return true
    }

    return matches(#"^[^./\\][^/\\]*\.[^./\\\s][^/\\\s]*$"#, text)
  }

  private static func matches(
    _ pattern: String,
    _ text: String,
    options: String.CompareOptions = .regularExpression
  ) -> Bool {
    text.range(of: pattern, options: options) != nil
  }

  private static func unquote(_ text: String) -> (text: String, wasQuoted: Bool) {
    guard text.count >= 2,
          let first = text.first,
          let last = text.last,
          first == last,
          "\"'`".contains(first) else {
      return (text, false)
    }

    return (String(text.dropFirst().dropLast()), true)
  }

  private static func hasUnescapedWhitespace(_ text: String) -> Bool {
    var isEscaped = false

    for scalar in text.unicodeScalars {
      if CharacterSet.whitespacesAndNewlines.contains(scalar) && !isEscaped {
        return true
      }

      if scalar == "\\" {
        isEscaped.toggle()
      } else {
        isEscaped = false
      }
    }

    return false
  }
}

private struct TranslationCandidateDecision {
  let shouldTranslate: Bool
  let context: [String: Any]
  let language: String?
  let languageConfidence: Double?
  let naturalLanguageScore: Int?

  static func allow(
    language: String,
    languageConfidence: Double,
    naturalLanguageScore: Int,
    context: [String: Any]
  ) -> TranslationCandidateDecision {
    TranslationCandidateDecision(
      shouldTranslate: true,
      context: context,
      language: language,
      languageConfidence: languageConfidence,
      naturalLanguageScore: naturalLanguageScore
    )
  }

  static func skip(
    reason: String,
    language: String? = nil,
    languageConfidence: Double? = nil,
    naturalLanguageScore: Int? = nil,
    context: [String: Any]
  ) -> TranslationCandidateDecision {
    var context = context
    context["reason"] = reason

    if let language {
      context["recognized_language"] = language
    }
    if let languageConfidence {
      context["recognized_language_confidence"] = languageConfidence
    }
    if let naturalLanguageScore {
      context["natural_language_score"] = naturalLanguageScore
    }

    return TranslationCandidateDecision(
      shouldTranslate: false,
      context: context,
      language: language,
      languageConfidence: languageConfidence,
      naturalLanguageScore: naturalLanguageScore
    )
  }
}

private struct LanguageCandidate {
  let language: NLLanguage
  let confidence: Double
}

private struct NaturalLanguageFeatures {
  let letterRatio: Double
  let digitRatio: Double
  let codeSymbolRatio: Double
  let englishWordCount: Int
  let hangulCount: Int
  let hasSentencePunctuation: Bool
  let hasCommonEnglishFunctionWord: Bool
  let hasKoreanSentenceEnding: Bool
  let hasVeryLongSingleToken: Bool

  init(_ text: String) {
    let scalars = Array(text.unicodeScalars)
    let scalarCount = max(scalars.count, 1)
    let codeSymbolSet = CharacterSet(charactersIn: "{}[]();=<>`|\\")

    let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
    let digitCount = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
    let codeSymbolCount = scalars.filter { codeSymbolSet.contains($0) }.count

    letterRatio = Double(letterCount) / Double(scalarCount)
    digitRatio = Double(digitCount) / Double(scalarCount)
    codeSymbolRatio = Double(codeSymbolCount) / Double(scalarCount)
    englishWordCount = Self.countEnglishWords(text)
    hangulCount = scalars.filter(\.isHangul).count
    hasSentencePunctuation = text.range(of: #"[.!?。！？]"#, options: .regularExpression) != nil
    hasCommonEnglishFunctionWord = Self.containsCommonEnglishFunctionWord(text)
    hasKoreanSentenceEnding = Self.containsKoreanSentenceEnding(text)
    hasVeryLongSingleToken = text
      .components(separatedBy: .whitespacesAndNewlines)
      .contains { $0.count >= 35 }
  }

  func logContext(
    textLength: Int,
    reason: String,
    minimumScore: Int,
    language: String,
    languageConfidence: Double,
    score: Int
  ) -> [String: Any] {
    [
      "reason": reason,
      "text_length": textLength,
      "minimum_natural_language_score": minimumScore,
      "natural_language_score": score,
      "recognized_language": language,
      "recognized_language_confidence": languageConfidence,
      "letter_ratio": letterRatio,
      "digit_ratio": digitRatio,
      "code_symbol_ratio": codeSymbolRatio,
      "english_word_count": englishWordCount,
      "hangul_count": hangulCount,
      "has_sentence_punctuation": hasSentencePunctuation,
      "has_common_english_function_word": hasCommonEnglishFunctionWord,
      "has_korean_sentence_ending": hasKoreanSentenceEnding,
      "has_very_long_single_token": hasVeryLongSingleToken
    ]
  }

  private static func countEnglishWords(_ text: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z]+(?:'[A-Za-z]+)?"#) else {
      return 0
    }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.numberOfMatches(in: text, range: range)
  }

  private static func containsCommonEnglishFunctionWord(_ text: String) -> Bool {
    let commonWords = [
      "the", "a", "an", "is", "are", "was", "were",
      "i", "you", "we", "they", "he", "she",
      "to", "for", "of", "in", "on", "with",
      "this", "that", "it", "not", "do", "does",
      "can", "could", "should", "would", "what", "why", "how"
    ]

    return commonWords.contains { word in
      let escapedWord = NSRegularExpression.escapedPattern(for: word)
      return text.range(
        of: #"(?i)\b\#(escapedWord)\b"#,
        options: .regularExpression
      ) != nil
    }
  }

  private static func containsKoreanSentenceEnding(_ text: String) -> Bool {
    let endings = [
      "합니다", "했습니다", "입니다", "이었다", "같아요", "같습니다",
      "네요", "어요", "아요", "습니다", "니까", "는데", "지만",
      "그리고", "하지만", "그래서", "때문에"
    ]

    return endings.contains { text.contains($0) }
  }
}

private struct TranslationDirection: Sendable {
  let sourceName: String
  let targetName: String

  static func detect(_ text: String) -> TranslationDirection? {
    var hasHangul = false
    var hasLatin = false

    for scalar in text.unicodeScalars {
      if scalar.isHangul {
        hasHangul = true
      } else if scalar.isLatinLetter {
        hasLatin = true
      }

      if hasHangul {
        return TranslationDirection(sourceName: "Korean", targetName: "English")
      }
    }

    guard hasLatin else { return nil }
    return TranslationDirection(sourceName: "English", targetName: "Korean")
  }
}

private extension UnicodeScalar {
  var isHangul: Bool {
    (0x1100...0x11FF).contains(value) ||
      (0x3130...0x318F).contains(value) ||
      (0xA960...0xA97F).contains(value) ||
      (0xAC00...0xD7A3).contains(value) ||
      (0xD7B0...0xD7FF).contains(value)
  }

  var isLatinLetter: Bool {
    (0x0041...0x005A).contains(value) || (0x0061...0x007A).contains(value)
  }
}

private struct ChatCompletionRequest: Encodable {
  let model: String
  let messages: [ChatMessage]
  let temperature: Double
  let thinking: ThinkingMode
}

private struct ChatMessage: Codable {
  let role: String
  let content: String?
}

private struct ThinkingMode: Encodable {
  let type: String
}

private struct ChatCompletionResponse: Decodable {
  let choices: [Choice]

  struct Choice: Decodable {
    let message: ChatMessage
  }
}

private enum TranslationError: LocalizedError {
  case invalidResponse
  case emptyTranslation
  case requestFailed(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Invalid response from DeepSeek."
    case .emptyTranslation:
      return "DeepSeek returned an empty translation."
    case let .requestFailed(statusCode, message):
      return "DeepSeek request failed with status \(statusCode): \(message)"
    }
  }
}
