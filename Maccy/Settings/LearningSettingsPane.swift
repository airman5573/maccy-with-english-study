import AppKit
import SwiftData
import SwiftUI

private struct TranslationStudySection: Identifiable {
  let date: Date
  let items: [TranslationStudyItem]

  var id: Date { date }
}

private struct TranslationStudyDateExport: Encodable {
  let date: String
  let items: [TranslationStudyItemExport]
}

private struct TranslationStudyItemExport: Encodable {
  let originalText: String
  let translatedText: String
  let translatedAt: String
  let application: String?
  let sourceLanguage: String
  let targetLanguage: String

  enum CodingKeys: String, CodingKey {
    case originalText
    case translatedText
    case translatedAt
    case application
    case sourceLanguage
    case targetLanguage
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(originalText, forKey: .originalText)
    try container.encode(translatedText, forKey: .translatedText)
    try container.encode(translatedAt, forKey: .translatedAt)
    try container.encode(application, forKey: .application)
    try container.encode(sourceLanguage, forKey: .sourceLanguage)
    try container.encode(targetLanguage, forKey: .targetLanguage)
  }
}

struct LearningSettingsPane: View {
  @Query(sort: \TranslationStudyItem.translatedAt, order: .reverse)
  private var items: [TranslationStudyItem]

  @State private var showDeleteAllConfirmation = false
  @State private var statusMessage: String?
  @State private var statusMessageIsError = false

  private var sections: [TranslationStudySection] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: items) { item in
      calendar.startOfDay(for: item.translatedAt)
    }

    return grouped.keys
      .sorted(by: >)
      .map { date in
        TranslationStudySection(
          date: date,
          items: (grouped[date] ?? []).sorted { $0.translatedAt > $1.translatedAt }
        )
      }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center) {
        Text("Description", tableName: "LearningSettings")
          .fixedSize(horizontal: false, vertical: true)
          .foregroundStyle(.gray)
          .controlSize(.small)

        Spacer()

        Button(role: .destructive) {
          showDeleteAllConfirmation = true
        } label: {
          Text("DeleteAll", tableName: "LearningSettings")
        }
        .disabled(items.isEmpty)
      }

      if items.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
              sectionView(section)
            }
          }
          .padding(.vertical, 4)
        }
      }

      if let statusMessage {
        Text(statusMessage)
          .fixedSize(horizontal: false, vertical: true)
          .foregroundStyle(statusMessageIsError ? .red : .green)
          .controlSize(.small)
      }
    }
    .frame(minWidth: 560, minHeight: 420)
    .padding()
    .confirmationDialog(
      Text("DeleteAllConfirmationTitle", tableName: "LearningSettings"),
      isPresented: $showDeleteAllConfirmation
    ) {
      Button(role: .destructive) {
        deleteAll()
      } label: {
        Text("DeleteAllConfirm", tableName: "LearningSettings")
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("DeleteAllConfirmationMessage", tableName: "LearningSettings")
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Spacer()
      Text("EmptyTitle", tableName: "LearningSettings")
        .font(.headline)
      Text("EmptyDescription", tableName: "LearningSettings")
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func sectionView(_ section: TranslationStudySection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(section.date.formatted(date: .long, time: .omitted))
          .font(.headline)

        Spacer()

        Button {
          copyJSON(section)
        } label: {
          Text("CopyDate", tableName: "LearningSettings")
        }
        .controlSize(.small)

        Button(role: .destructive) {
          delete(section.items)
        } label: {
          Text("DeleteDate", tableName: "LearningSettings")
        }
        .controlSize(.small)
      }

      ForEach(section.items) { item in
        TranslationStudyPairView(item: item)
      }
    }
  }

  private func delete(_ items: [TranslationStudyItem]) {
    do {
      try TranslationStudyHistory.delete(items)
      clearStatus()
    } catch {
      showStatus(error.localizedDescription, isError: true)
    }
  }

  private func deleteAll() {
    do {
      try TranslationStudyHistory.deleteAll()
      clearStatus()
    } catch {
      showStatus(error.localizedDescription, isError: true)
    }
  }

  private func copyJSON(_ section: TranslationStudySection) {
    do {
      let export = TranslationStudyDateExport(
        date: exportDateString(section.date),
        items: section.items.map { item in
          TranslationStudyItemExport(
            originalText: item.originalText,
            translatedText: item.translatedText,
            translatedAt: exportDateTimeString(item.translatedAt),
            application: item.application,
            sourceLanguage: item.sourceLanguage,
            targetLanguage: item.targetLanguage
          )
        }
      )

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
      let data = try encoder.encode(export)
      guard let json = String(data: data, encoding: .utf8) else {
        showCopyFailure(reason: NSLocalizedString("CopyDateEncodingFailure", tableName: "LearningSettings", comment: ""))
        return
      }

      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      guard pasteboard.setString(json, forType: .string) else {
        showCopyFailure(reason: NSLocalizedString("CopyDatePasteboardFailure", tableName: "LearningSettings", comment: ""))
        return
      }

      showStatus(NSLocalizedString("CopyDateSuccess", tableName: "LearningSettings", comment: ""), isError: false)
    } catch {
      showCopyFailure(reason: error.localizedDescription)
    }
  }

  private func exportDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = Calendar.current.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private func exportDateTimeString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private func showCopyFailure(reason: String) {
    showStatus(
      String(format: NSLocalizedString("CopyDateFailure", tableName: "LearningSettings", comment: ""), reason),
      isError: true
    )
  }

  private func showStatus(_ message: String, isError: Bool) {
    statusMessage = message
    statusMessageIsError = isError
  }

  private func clearStatus() {
    statusMessage = nil
    statusMessageIsError = false
  }
}

private struct TranslationStudyPairView: View {
  let item: TranslationStudyItem

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      textBlock(title: Text("Original", tableName: "LearningSettings"), text: item.originalText)
      Divider()
      textBlock(title: Text("Translation", tableName: "LearningSettings"), text: item.translatedText)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.secondary.opacity(0.2))
    )
  }

  private func textBlock(title: Text, text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      title
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(text)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#Preview {
  LearningSettingsPane()
    .environment(\.locale, .init(identifier: "ko"))
    .modelContainer(Storage.shared.container)
}
