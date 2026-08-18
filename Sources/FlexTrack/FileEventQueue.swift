import Foundation

public actor FileEventQueue: EventQueue {
  private let fileURL: URL
  private var items: [QueuedEvent]
  private let encoder: JSONEncoder

  public init(fileURL: URL) throws {
    self.fileURL = fileURL
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if FileManager.default.fileExists(atPath: fileURL.path) {
      self.items = try decoder.decode([QueuedEvent].self, from: Data(contentsOf: fileURL))
    } else {
      self.items = []
    }
    self.encoder = JSONEncoder()
    self.encoder.dateEncodingStrategy = .iso8601
    self.encoder.outputFormatting = [.sortedKeys]
  }

  public func enqueue(_ item: QueuedEvent) throws {
    guard !items.contains(where: { $0.id == item.id }) else { return }
    var updated = items
    updated.append(item)
    try persist(updated)
    items = updated
  }

  public func read(limit: Int) throws -> [QueuedEvent] {
    guard limit > 0 else { throw FlexTrackError.invalidLimit }
    return Array(items.prefix(limit))
  }

  public func replace(_ item: QueuedEvent) throws {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    var updated = items
    updated[index] = item
    try persist(updated)
    items = updated
  }

  public func remove(id: String) throws {
    let updated = items.filter { $0.id != id }
    guard updated.count != items.count else { return }
    try persist(updated)
    items = updated
  }

  public func size() -> Int { items.count }

  public func clear() throws {
    try persist([])
    items = []
  }

  private func persist(_ value: [QueuedEvent]) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try encoder.encode(value)
    try data.write(to: fileURL, options: [.atomic])
  }
}
