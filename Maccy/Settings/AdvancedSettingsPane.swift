import SwiftUI
import Defaults

struct AdvancedSettingsPane: View {
  @Default(.translationEnabled) private var translationEnabled
  @Default(.translationModel) private var translationModel

  @State private var translationAPIKey = DeepSeekAPIKeyStore.apiKey

  var body: some View {
    VStack(alignment: .leading) {
      Defaults.Toggle(key: .ignoreEvents) {
        Text("TurnOff", tableName: "AdvancedSettings")
      }
      Text("TurnOffDescription", tableName: "AdvancedSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      Text("TurnOffShellScript", tableName: "AdvancedSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .font(.system(size: 11, design: .monospaced))
        .controlSize(.small)
        .padding(.vertical, 2)
      Text("TurnOffViaMenuIconDescription", tableName: "AdvancedSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      Text("TurnOffNextShellScript", tableName: "AdvancedSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .font(.system(size: 11, design: .monospaced))
        .controlSize(.small)
        .padding(.vertical, 2)

      Divider()

      Text("DeepSeekTranslation", tableName: "AdvancedSettings")
        .font(.headline)

      Defaults.Toggle(key: .translationEnabled) {
        Text("DeepSeekTranslationEnabled", tableName: "AdvancedSettings")
      }

      Text("DeepSeekTranslationDescription", tableName: "AdvancedSettings")
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)

      VStack(alignment: .leading) {
        Text("DeepSeekAPIKey", tableName: "AdvancedSettings")
          .controlSize(.small)
        SecureField(
          String(localized: "DeepSeekAPIKeyPlaceholder", table: "AdvancedSettings"),
          text: $translationAPIKey
        )
        .textFieldStyle(.roundedBorder)
        .onChange(of: translationAPIKey) { _, newValue in
          DeepSeekAPIKeyStore.apiKey = newValue
        }
        .help(Text("DeepSeekAPIKeyTooltip", tableName: "AdvancedSettings"))

        Text("DeepSeekModel", tableName: "AdvancedSettings")
          .controlSize(.small)
        TextField("", text: $translationModel)
          .textFieldStyle(.roundedBorder)
          .help(Text("DeepSeekModelTooltip", tableName: "AdvancedSettings"))
      }
      .disabled(!translationEnabled)

      Divider()

      Defaults.Toggle(key: .clearOnQuit) {
        Text("ClearHistoryOnQuit", tableName: "AdvancedSettings")
      }.help(Text("ClearHistoryOnQuitTooltip", tableName: "AdvancedSettings"))

      Defaults.Toggle(key: .clearSystemClipboard) {
        Text("ClearSystemClipboard", tableName: "AdvancedSettings")
      }.help(Text("ClearSystemClipboardTooltip", tableName: "AdvancedSettings"))
    }
    .frame(minWidth: 350, maxWidth: 450)
    .padding()
    .onAppear {
      translationAPIKey = DeepSeekAPIKeyStore.apiKey
    }
  }
}

#Preview {
  AdvancedSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
