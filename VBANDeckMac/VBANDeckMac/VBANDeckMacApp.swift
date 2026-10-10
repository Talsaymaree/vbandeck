import SwiftUI

@main
struct VBANDeckMacApp: App {
    @StateObject private var model = MacStreamingViewModel()

    var body: some Scene {
        WindowGroup {
            MacContentView(model: model)
        }
    }
}
