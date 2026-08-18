import FlexTrack
import SwiftUI

struct DashboardView: View {
  @ObservedObject var model: SampleViewModel

  var body: some View {
    SampleScroll(title: "Signal board", subtitle: "A live view of your analytics pipeline.") {
      SignalHero(isReady: model.isReady, isOnline: model.isOnline)
      HStack(spacing: 12) {
        MetricCard(value: "\(model.sentCount)", label: "Events", color: FlexPalette.signal)
        MetricCard(value: "\(model.queueCount)", label: "Queued", color: FlexPalette.warning)
      }
      SectionLabel("Pipeline")
      PipelineRow(symbol: "arrow.triangle.branch", title: "Routing", value: "Deterministic")
      PipelineRow(
        symbol: "checkmark.shield.fill", title: "Consent",
        value: model.generalConsent ? "Granted" : "Denied")
      PipelineRow(
        symbol: "point.3.filled.connected.trianglepath.dotted", title: "Tracker",
        value: "sample_tracker")
    }
    .navigationTitle("FlexTrack")
  }
}

struct EventsView: View {
  @ObservedObject var model: SampleViewModel

  var body: some View {
    SampleScroll(title: "Event lab", subtitle: "Send known payloads and inspect every decision.") {
      ForEach(EventTemplate.samples) { template in
        Button {
          Task { await model.track(template) }
        } label: {
          HStack(spacing: 14) {
            Image(systemName: template.symbol)
              .font(.title3).frame(width: 44, height: 44)
              .background(FlexPalette.violet.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
              Text(template.title).font(.headline)
              Text(template.description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right").foregroundStyle(FlexPalette.signal)
          }
          .padding(16).background(FlexPalette.panel, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).disabled(model.isBusy || !model.isReady)
      }
    }
    .navigationTitle("Events")
  }
}

struct QueueView: View {
  @ObservedObject var model: SampleViewModel

  var body: some View {
    SampleScroll(
      title: "Offline queue", subtitle: "The durable hand-off between no signal and delivery."
    ) {
      VStack(spacing: 8) {
        Text("\(model.queueCount)").font(.system(size: 72, weight: .black, design: .rounded))
        Text("events waiting").font(.subheadline).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity).padding(.vertical, 28)
      .background(
        LinearGradient(
          colors: [FlexPalette.warning.opacity(0.22), FlexPalette.panel], startPoint: .topLeading,
          endPoint: .bottomTrailing),
        in: RoundedRectangle(cornerRadius: 24)
      )
      Button {
        Task { await model.flush() }
      } label: {
        Label(
          model.isOnline ? "Flush queue" : "Connect network to flush",
          systemImage: "arrow.triangle.2.circlepath"
        )
        .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 14)
      }
      .buttonStyle(.borderedProminent).tint(FlexPalette.signal)
      .disabled(!model.isOnline || model.isBusy || model.queueCount == 0)
      Text(
        "Turn Network off in Settings, send events, close the app, then reopen it. The count is restored from FileEventQueue."
      )
      .font(.footnote).foregroundStyle(.secondary).padding(4)
    }
    .navigationTitle("Queue")
  }
}

struct LogsView: View {
  @ObservedObject var model: SampleViewModel

  var body: some View {
    SampleScroll(
      title: "Delivery console", subtitle: "Names, values, targets, and outcomes—without guesswork."
    ) {
      if model.logs.isEmpty {
        EmptyLogView()
      } else {
        ForEach(model.logs) { log in LogCard(log: log) }
        Button("Clear logs", role: .destructive) { model.clearLogs() }
          .frame(maxWidth: .infinity)
      }
    }
    .navigationTitle("Logs")
  }
}

struct SettingsView: View {
  @ObservedObject var model: SampleViewModel

  var body: some View {
    SampleScroll(
      title: "Runtime controls", subtitle: "Persisted switches for repeatable delivery tests."
    ) {
      SettingsCard {
        Toggle(isOn: $model.isOnline) { Label("Network available", systemImage: "network") }
        Divider()
        Toggle(isOn: $model.generalConsent) {
          Label("General consent", systemImage: "checkmark.shield")
        }
        Divider()
        Toggle(isOn: $model.piiConsent) { Label("PII consent", systemImage: "person.badge.key") }
      }
      SectionLabel("Package")
      PipelineRow(symbol: "shippingbox.fill", title: "Version", value: FlexTrack.version)
      PipelineRow(symbol: "curlybraces", title: "Module", value: "FlexTrack")
      PipelineRow(symbol: "iphone", title: "Sample", value: "SwiftUI + MVVM")
      Text(
        "These switches survive app restarts through UserDefaults. Event payloads are persisted only in the SDK queue file."
      )
      .font(.footnote).foregroundStyle(.secondary).padding(4)
    }
    .navigationTitle("Settings")
  }
}

private struct SampleScroll<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold))
          Text(subtitle).foregroundStyle(.secondary)
        }.padding(.bottom, 6)
        content
      }.padding(20)
    }
    .background(FlexPalette.canvas.ignoresSafeArea())
  }
}

private struct SignalHero: View {
  let isReady: Bool
  let isOnline: Bool
  var body: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 8) {
        Text(isReady ? "SDK READY" : "STARTING").font(.caption.monospaced().bold()).foregroundStyle(
          FlexPalette.signal)
        Text(isOnline ? "Live signal" : "Capturing offline")
          .font(.system(size: 30, weight: .bold, design: .rounded))
      }
      Spacer()
      Circle().fill(isOnline ? FlexPalette.success : FlexPalette.warning)
        .frame(width: 14, height: 14).shadow(
          color: isOnline ? FlexPalette.success : FlexPalette.warning, radius: 9)
    }
    .padding(22)
    .background(
      LinearGradient(
        colors: [FlexPalette.violet.opacity(0.40), FlexPalette.panel], startPoint: .topLeading,
        endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 24)
    )
  }
}

private struct MetricCard: View {
  let value: String
  let label: String
  let color: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value).font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(color)
      Text(label).font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
      .background(FlexPalette.panel, in: RoundedRectangle(cornerRadius: 18))
  }
}

private struct PipelineRow: View {
  let symbol: String
  let title: String
  let value: String
  var body: some View {
    HStack {
      Image(systemName: symbol).foregroundStyle(FlexPalette.signal).frame(width: 28)
      Text(title)
      Spacer()
      Text(value).font(.caption.monospaced()).foregroundStyle(.secondary)
    }.padding(16).background(FlexPalette.panel, in: RoundedRectangle(cornerRadius: 16))
  }
}

private struct SectionLabel: View {
  let value: String
  init(_ value: String) { self.value = value }
  var body: some View {
    Text(value.uppercased()).font(.caption.monospaced().bold()).foregroundStyle(.secondary).padding(
      .top, 8)
  }
}

private struct SettingsCard<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    VStack(spacing: 14) { content }.padding(16).background(
      FlexPalette.panel, in: RoundedRectangle(cornerRadius: 18))
  }
}

private struct LogCard: View {
  let log: SampleLog
  var color: Color {
    switch log.kind {
    case .delivered: FlexPalette.success
    case .queued: FlexPalette.warning
    case .error: .red
    default: FlexPalette.signal
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(log.kind.rawValue).font(.caption.monospaced().bold()).foregroundStyle(color)
        Spacer()
        Text(log.timestamp, style: .time).font(.caption2.monospaced()).foregroundStyle(.secondary)
      }
      Text(log.eventName).font(.headline.monospaced())
      if !log.properties.isEmpty {
        Text(render(log.properties)).font(.caption.monospaced()).foregroundStyle(.secondary)
      }
      Text(log.message).font(.caption).foregroundStyle(.secondary)
    }.padding(16).background(FlexPalette.panel, in: RoundedRectangle(cornerRadius: 16))
  }

  private func render(_ values: [String: JSONValue]) -> String {
    values.keys.sorted().map { "\($0)=\(String(describing: values[$0]!))" }.joined(separator: "  ")
  }
}

private struct EmptyLogView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "terminal").font(.system(size: 36)).foregroundStyle(FlexPalette.signal)
      Text("No decisions yet").font(.headline)
      Text("Send an event to populate the delivery console.").font(.caption).foregroundStyle(
        .secondary)
    }.frame(maxWidth: .infinity).padding(.vertical, 36).background(
      FlexPalette.panel, in: RoundedRectangle(cornerRadius: 20))
  }
}
