/// Presentation states keep an idle microphone distinct from live, unprocessed audio.
enum MenuActivity: Equatable {
    case idle
    case starting
    case installing
    case removing
    case stopping
    case running(microphone: String, cleaning: Bool)

    var isBusy: Bool {
        switch self {
        case .starting, .installing, .removing, .stopping: true
        case .idle, .running: false
        }
    }

    var isRouting: Bool {
        if case .running = self { return true }
        return false
    }

    var isCleaning: Bool {
        if case .running(_, let cleaning) = self { return cleaning }
        return false
    }

    var microphone: String? {
        if case .running(let name, _) = self { return name }
        return nil
    }

    var title: String {
        switch self {
        case .idle: "Not running"
        case .starting: "Starting microphone…"
        case .installing: "Setting up microphone…"
        case .removing: "Removing virtual microphone…"
        case .stopping: "Stopping microphone…"
        case .running(_, true): "Removing noise"
        case .running(_, false): "Passing original audio"
        }
    }

    var symbol: String {
        if isBusy { return "waveform.badge.ellipsis" }
        return isCleaning ? "waveform.circle.fill" : "waveform.circle"
    }
}

enum MenuNotice: Equatable {
    case microphonePermission
    case failure(title: String, detail: String)
    case information(String)

    var title: String {
        switch self {
        case .microphonePermission: "Microphone access required"
        case .failure(let title, _), .information(let title): title
        }
    }

    var detail: String? {
        if case .failure(_, let detail) = self { return detail }
        return nil
    }
}

struct MenuState: Equatable {
    var activity: MenuActivity = .idle
    var driverInstalled = false
    var notice: MenuNotice?

    var accessibilityLabel: String {
        "LucidMic, \(activity.title)" + (notice.map { ", \($0.title)" } ?? "")
    }
}

enum MenuCommand: String {
    case toggleNoiseRemoval, microphoneSettings, details, settings, help, about, quit
}
