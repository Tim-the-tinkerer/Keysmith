import Foundation

enum WorkspaceStore {
    static let key = "workspace"
}

enum Workspace: String, CaseIterable, Identifiable {
    case password
    case hex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: return "Password"
        case .hex: return "Hex"
        }
    }
}

@MainActor
final class ShellModel: ObservableObject {
    @Published var mode: Workspace

    init() {
        if let raw = UserDefaults.standard.string(forKey: WorkspaceStore.key),
           let parsed = Workspace(rawValue: raw) {
            mode = parsed
        } else {
            mode = .password
        }
    }
}
