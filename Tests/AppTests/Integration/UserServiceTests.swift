import XCTVapor
import Fluent
@testable import App

final class UserServiceTests: XCTestCase {

    func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await test(app)
            try await app.autoRevert()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    
    func test_fetchUserID_withValidToken_returnsUserID() async throws {
        try await withApp { app in
            // 1. Создаём пользователя и токен
            let user = User(username: "unituser", email: "unit@mail.com", password: try Bcrypt.hash("unitpass"))
            try await user.save(on: app.db)
            let token = try Token.generate(for: user)
            try await token.save(on: app.db)
            
            // 2. Делаем моковый Vapor Request с Bearer
            var headers = HTTPHeaders()
            headers.bearerAuthorization = .init(token: token.value)
            let req = Request(application: app, on: app.eventLoopGroup.next())
            req.headers = headers

            // 3. UserService работает с настоящей базой
            let service = UserService(db: app.db)
            let userID = try await service.fetchUserID(req: req)
            XCTAssertEqual(userID, try user.requireID(), "Должен вернуть правильный userID")
        }
    }
    
    func test_fetchUserID_missingToken_throwsUnauthorized() async throws {
        try await withApp { app in
            let req = Request(application: app, on: app.eventLoopGroup.next())
            let service = UserService(db: app.db)
            
            do {
                _ = try await service.fetchUserID(req: req)
                XCTFail("Ожидалась ошибка .unauthorized при отсутствии токена")
            } catch let error as AbortError {
                XCTAssertEqual(error.status, .unauthorized)
            } catch {
                XCTFail("Неожиданная ошибка: \(error)")
            }
        }
    }
    
    func test_fetchUserID_invalidToken_throwsUnauthorized() async throws {
        try await withApp { app in
            // 1. Моковый Request с несуществующим токеном
            var headers = HTTPHeaders()
            headers.bearerAuthorization = .init(token: "nonexistent_token")
            let req = Request(application: app, on: app.eventLoopGroup.next())
            req.headers = headers

            let service = UserService(db: app.db)
            do {
                _ = try await service.fetchUserID(req: req)
                XCTFail("Ожидалась ошибка .unauthorized при невалидном токене")
            } catch let error as AbortError {
                XCTAssertEqual(error.status, .unauthorized)
            } catch {
                XCTFail("Неожиданная ошибка: \(error)")
            }
        }
    }
}
