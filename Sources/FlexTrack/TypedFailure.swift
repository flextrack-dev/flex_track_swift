/// Stable failure categories for logging, metrics, and recovery decisions.
public enum FlexTrackFailureCategory: String, Sendable, Equatable {
  case configuration, routing, tracker, lifecycle, queue
}

/// Swift-native typed error metadata. Concrete errors remain enums for exhaustive switching.
public protocol FlexTrackTypedError: Error, Sendable {
  var category: FlexTrackFailureCategory { get }
  var code: String { get }
}

extension FlexTrackError: FlexTrackTypedError {
  public var category: FlexTrackFailureCategory {
    switch self {
    case .invalidLimit: .queue
    case .clientNotStarted, .registryAlreadyStarted: .lifecycle
    case .invalidTrackerID, .duplicateTracker, .trackerUnavailable: .tracker
    }
  }

  public var code: String {
    switch self {
    case .invalidTrackerID: "INVALID_TRACKER_ID"
    case .duplicateTracker: "DUPLICATE_TRACKER"
    case .registryAlreadyStarted: "REGISTRY_ALREADY_STARTED"
    case .trackerUnavailable: "TRACKER_UNAVAILABLE"
    case .clientNotStarted: "CLIENT_NOT_STARTED"
    case .invalidLimit: "INVALID_LIMIT"
    }
  }
}

extension FlexTrackConfigurationError: FlexTrackTypedError {
  public var category: FlexTrackFailureCategory { .configuration }

  public var code: String {
    switch self {
    case .empty: "EMPTY_VALUE"
    case .unknownGroup: "UNKNOWN_GROUP"
    case .unknownCategory: "UNKNOWN_CATEGORY"
    case .invalidSamplingRate: "INVALID_SAMPLING_RATE"
    case .missingTarget: "MISSING_TARGET"
    case .missingTracker: "MISSING_TRACKER"
    }
  }
}
