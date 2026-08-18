import Foundation

public struct FlexTrackLogger: Sendable {
  private let sink: @Sendable (String) -> Void

  public init(_ sink: @escaping @Sendable (String) -> Void) {
    self.sink = sink
  }

  public func log(_ message: @autoclosure () -> String) {
    sink(message())
  }

  public static let disabled = FlexTrackLogger { _ in }

  public static let debugConsole = FlexTrackLogger { message in
    #if DEBUG
      print("FlexTrack \(message)")
    #endif
  }
}
