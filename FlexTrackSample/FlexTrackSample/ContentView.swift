import SwiftUI

struct ContentView: View {
  @StateObject private var model = SampleViewModel()

  var body: some View {
    TabView {
      NavigationView { DashboardView(model: model) }
        .tabItem { Label("Home", systemImage: "waveform.path.ecg") }
      NavigationView { EventsView(model: model) }
        .tabItem { Label("Events", systemImage: "paperplane.fill") }
      NavigationView { QueueView(model: model) }
        .tabItem { Label("Queue", systemImage: "tray.full.fill") }
      NavigationView { LogsView(model: model) }
        .tabItem { Label("Logs", systemImage: "terminal.fill") }
      NavigationView { SettingsView(model: model) }
        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
    }
    .tint(FlexPalette.signal)
    .task { await model.start() }
  }
}

#Preview { ContentView() }
