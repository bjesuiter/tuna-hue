import Foundation
import Security

enum HueGroupKind: String, Sendable {
  case room, zone

  var label: String { self == .room ? "Hue Room" : "Hue Zone" }
}

struct HueGroup: Sendable {
  let id: UUID
  let name: String
  let kind: HueGroupKind
  let lightID: UUID
}

enum HueError: LocalizedError {
  case configuration(String)
  case authorization
  case http(Int)
  case response
  case rejected
  case bridgeChanged

  var errorDescription: String? {
    switch self {
    case .configuration(let message): return message
    case .authorization: return "Hue rejected the application key. Check the Hue extension settings."
    case .http(let status): return "The Hue bridge returned HTTP \(status)."
    case .response: return "The Hue bridge returned an unexpected response."
    case .rejected: return "The Hue bridge reported an error for this request."
    case .bridgeChanged: return "The Hue bridge changed. Rescan Hue Groups and choose the group again."
    }
  }
}

struct HueBridge: Sendable {
  let id: String
  private let baseURL: URL
  private let key: String
  private let trust: HueTrust

  init(address: String, id: String, key: String, caPEM: String) throws {
    guard id.utf8.count == 16, id.utf8.allSatisfy({
      (48...57).contains($0) || (97...102).contains($0)
    }) else {
      throw HueError.configuration("Enter the 16-digit hexadecimal Hue bridge ID.")
    }

    var components = URLComponents()
    components.scheme = "https"
    components.host = address
    let allowedHost = CharacterSet(charactersIn:
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
    guard !address.isEmpty, address.unicodeScalars.allSatisfy(allowedHost.contains),
          let baseURL = components.url else {
      throw HueError.configuration("Enter the bridge IPv4 address or local hostname.")
    }
    guard !key.isEmpty, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
      throw HueError.configuration("Enter the Hue application key.")
    }

    self.id = id
    self.baseURL = baseURL
    self.key = key
    self.trust = try HueTrust(bridgeID: id, caPEM: caPEM)
  }

  func groups() async throws -> [HueGroup] {
    async let rooms = groups(of: .room)
    async let zones = groups(of: .zone)
    return try await rooms + zones
  }

  func setPower(_ on: Bool, lightID: UUID) async throws {
    let result: [Service] = try await request(
      "grouped_light/\(lightID.uuidString.lowercased())",
      body: JSONEncoder().encode(Power(on: .init(on: on)))
    )
    guard result.contains(where: { $0.rid == lightID && $0.rtype == "grouped_light" }) else {
      throw HueError.response
    }
  }

  private func groups(of kind: HueGroupKind) async throws -> [HueGroup] {
    let resources: [GroupResource] = try await request(kind.rawValue)
    return resources.compactMap { resource in
      guard let service = resource.services.first(where: { $0.rtype == "grouped_light" }) else {
        return nil
      }
      return HueGroup(id: resource.id, name: resource.metadata.name, kind: kind, lightID: service.rid)
    }
  }

  private func request<Value: Decodable>(_ path: String, body: Data? = nil) async throws -> [Value] {
    let url = baseURL.appendingPathComponent("clip/v2/resource/\(path)")
    var request = URLRequest(url: url)
    request.setValue(key, forHTTPHeaderField: "hue-application-key")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpMethod = "PUT"
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 5
    config.timeoutIntervalForResource = 10
    config.tlsMinimumSupportedProtocolVersion = .TLSv12
    let session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw HueError.response }
    if http.statusCode == 401 || http.statusCode == 403 { throw HueError.authorization }
    guard (200..<300).contains(http.statusCode) else { throw HueError.http(http.statusCode) }

    let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: data)
    guard envelope.errors.isEmpty else { throw HueError.rejected }
    return envelope.data
  }
}

private struct GroupResource: Decodable {
  struct Metadata: Decodable { let name: String }
  let id: UUID
  let metadata: Metadata
  let services: [Service]
}

private struct Service: Decodable {
  let rid: UUID
  let rtype: String
}

private struct Envelope<Value: Decodable>: Decodable {
  struct APIError: Decodable {}
  let data: [Value]
  let errors: [APIError]
}

private struct Power: Encodable {
  struct State: Encodable { let on: Bool }
  let on: State
}

private final class HueTrust: NSObject, URLSessionTaskDelegate, Sendable {
  private let bridgeID: String
  private let anchors: [SecCertificate]

  init(bridgeID: String, caPEM: String) throws {
    self.bridgeID = bridgeID
    let pattern = /-----BEGIN CERTIFICATE-----([A-Za-z0-9+\/=\s]+)-----END CERTIFICATE-----/
    anchors = caPEM.matches(of: pattern).compactMap { match in
      let base64 = match.output.1.filter { !$0.isWhitespace }
      guard let der = Data(base64Encoded: base64) else { return nil }
      return SecCertificateCreateWithData(nil, der as CFData)
    }
    guard !anchors.isEmpty else {
      throw HueError.configuration("Choose the official Philips Hue root CA PEM file.")
    }
  }

  func urlSession(
    _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust,
          SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil)) == errSecSuccess,
          SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
          SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
          SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
          SecTrustEvaluateWithError(trust, nil),
          let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
          matchesBridgeID(leaf) else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }

  private func matchesBridgeID(_ certificate: SecCertificate) -> Bool {
    // Hue bridge certificates can carry the bridge ID only in the subject common name.
    var commonName: CFString?
    return SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess
      && (commonName as String?)?.lowercased() == bridgeID
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
