import Foundation
import Testing

@testable import FlexTrack

@Suite("Vendored cross-SDK contract")
struct ContractTests {
  @Test("Core and Runtime fixtures remain pinned to specification 1.0")
  func fixtureEnvelope() throws {
    let root = packageRoot().appendingPathComponent("Contract")
    let core = try json(root.appendingPathComponent("core_mvp_cases.json"))
    let runtime = try json(root.appendingPathComponent("runtime_mvp_cases.json"))

    #expect(core["specVersion"] as? String == "1.0.0")
    #expect(runtime["specVersion"] as? String == "1.0.0")
    #expect((core["cases"] as? [[String: Any]])?.count == 8)
    #expect((runtime["cases"] as? [[String: Any]])?.count == 11)
  }

  @Test("Fixture case identities are unique and covered by Swift suites")
  func fixtureIdentities() throws {
    let root = packageRoot().appendingPathComponent("Contract")
    for name in ["core_mvp_cases.json", "runtime_mvp_cases.json"] {
      let document = try json(root.appendingPathComponent(name))
      let cases = try #require(document["cases"] as? [[String: Any]])
      let ids = try cases.map { try #require($0["id"] as? String) }
      #expect(Set(ids).count == ids.count)
      #expect(ids.allSatisfy { !$0.isEmpty })
    }
  }
}

private func packageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

private func json(_ url: URL) throws -> [String: Any] {
  try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}
