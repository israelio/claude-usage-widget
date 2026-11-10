import Foundation

/// How many of our widgets are on the desktop. Polls every 2 s, but only while a view observes it.
@MainActor
final class WidgetStatus: ObservableObject {
    @Published private(set) var placedCount: Int?   // nil = unknown / checking
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let n = await WidgetConfigurations.current()?.count
                guard let self else { return }
                self.placedCount = n
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    deinit { task?.cancel() }
}
