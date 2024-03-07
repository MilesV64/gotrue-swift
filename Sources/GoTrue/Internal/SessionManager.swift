import Foundation
import KeychainAccess

struct StoredSession: Codable {
  var session: Session
  var expirationDate: Date
    
    var buffer: TimeInterval {
        return self.session.expiresIn - 30//self.session.expiresIn / 2
    }

  var isValid: Bool {
      if Date().addingTimeInterval(self.buffer) < expirationDate {
          return true
      } else {
          return false
      }
  }

  init(session: Session, expirationDate: Date? = nil) {
    self.session = session
    self.expirationDate = expirationDate ?? Date().addingTimeInterval(session.expiresIn)
  }
}

struct SessionManager {
  var session: () async throws -> Session
  var alwaysRefreshedSession: () async throws -> Session
  var update: (_ session: Session) async throws -> Void
  var remove: () async -> Void
}

extension SessionManager {
  static var live: Self {
    let instance = LiveSessionManager()
    return Self(
      session: { try await instance.session(alwaysRefresh: false) },
      alwaysRefreshedSession: { try await instance.session(alwaysRefresh: true) },
      update: { try await instance.update($0) },
      remove: { await instance.remove() }
    )
  }
}

private actor LiveSessionManager {
  private var task: Task<Session, Error>?

  func session(alwaysRefresh: Bool = false) async throws -> Session {
    if let task {
      return try await task.value
    }

    guard let currentSession = try Env.localStorage.getSession() else {
      throw GoTrueError.sessionNotFound
    }

    if !alwaysRefresh && currentSession.isValid {
//      let buffer = currentSession.buffer
//      let time = currentSession.expirationDate.timeIntervalSince(Date().addingTimeInterval(buffer))
//      print("GOTRUE: Refreshing auth session in \(time)s")
      return currentSession.session
    }

      print("reFRESHING")
    task = Task {
      defer { self.task = nil }

      let session = try await Env.sessionRefresher(currentSession.session.refreshToken)
      try update(session)
      //print("GOTRUE: Refreshed auth session")
      return session
    }

    return try await task!.value
  }

  func update(_ session: Session) throws {
    try Env.localStorage.storeSession(StoredSession(session: session))
  }

  func remove() {
    Env.localStorage.deleteSession()
  }
}

extension GoTrueLocalStorage {
  func getSession() throws -> StoredSession? {
    try retrieve(key: "supabase.session").flatMap {
      try JSONDecoder.goTrue.decode(StoredSession.self, from: $0)
    }
  }

  fileprivate func storeSession(_ session: StoredSession) throws {
    try store(key: "supabase.session", value: JSONEncoder.goTrue.encode(session))
  }

  fileprivate func deleteSession() {
    try? remove(key: "supabase.session")
  }
}
