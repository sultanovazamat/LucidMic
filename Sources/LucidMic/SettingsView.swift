import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(state: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "LucidMic Settings"
        window.contentView = NSHostingView(rootView: SettingsView(state: state))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var confirmsRemoval = false

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })
                )
                .help("Open LucidMic in the menu bar when you sign in. Noise removal starts when you turn it on.")
                if state.loginNeedsApproval {
                    Text("Allow LucidMic in Login Items to finish enabling launch at login.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = state.settingsError {
                    Text(error).font(.callout).foregroundStyle(.red)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                LabeledContent("Virtual Microphone", value: state.driverInstalled ? "Installed" : "Not Installed")
                if state.isBusy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(state.status).foregroundStyle(.secondary)
                    }
                }
                Button("Remove Virtual Microphone…", role: .destructive) { confirmsRemoval = true }
                    .disabled(!state.driverInstalled || state.isBusy)
                if let notice = state.notice {
                    Text(notice.title).font(.callout).foregroundStyle(.secondary)
                    if let detail = notice.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text(
                    "Removing the virtual microphone leaves LucidMic installed. Turning Noise Removal on sets it up again."
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 430)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { state.refresh() }
        .alert("Remove Virtual Microphone?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Microphone", role: .destructive) { Task { await state.removeDriver() } }
        } message: {
            Text(
                "This stops LucidMic, restores your physical microphone, and removes the virtual microphone. "
                    + "The audio service restarts, which can interrupt other audio apps. "
                    + "macOS will ask for administrator permission. LucidMic stays installed.")
        }
    }
}
