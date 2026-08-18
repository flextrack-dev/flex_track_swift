import Foundation

public enum JSONValue: Sendable, Codable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}

public struct FlexEvent: Sendable, Codable, Equatable {
  public let id: String
  public let timestamp: Date
  public let name: String
  public let properties: [String: JSONValue]
  public let category: String?
  public let containsPII: Bool
  public let requiresConsent: Bool
  public let isHighVolume: Bool
  public let isEssential: Bool
  public let userID: String?
  public let sessionID: String?

  public init(
    id: String = UUID().uuidString.lowercased(),
    timestamp: Date = Date(),
    name: String,
    properties: [String: JSONValue] = [:],
    category: String? = nil,
    containsPII: Bool = false,
    requiresConsent: Bool = true,
    isHighVolume: Bool = false,
    isEssential: Bool = false,
    userID: String? = nil,
    sessionID: String? = nil
  ) {
    precondition(!id.isEmpty, "event id cannot be empty")
    precondition(!name.isEmpty, "event name cannot be empty")
    self.id = id
    self.timestamp = timestamp
    self.name = name
    self.properties = properties
    self.category = category
    self.containsPII = containsPII
    self.requiresConsent = requiresConsent
    self.isHighVolume = isHighVolume
    self.isEssential = isEssential
    self.userID = userID
    self.sessionID = sessionID
  }

  public func enriched(with extraProperties: [String: JSONValue]) -> FlexEvent {
    FlexEvent(
      id: id,
      timestamp: timestamp,
      name: name,
      properties: properties.merging(extraProperties) { _, new in new },
      category: category,
      containsPII: containsPII,
      requiresConsent: requiresConsent,
      isHighVolume: isHighVolume,
      isEssential: isEssential,
      userID: userID,
      sessionID: sessionID
    )
  }
}

public typealias EventTransformer = @Sendable (FlexEvent) throws -> FlexEvent
