@testable import App
import XCTVapor
import Testing
import Fluent

@Suite("UsersController Tests", .serialized)
struct UsersControllerTests {
    
    let apiService = APIKeyService()
    
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            app.logger.logLevel = .error
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

    /**
     Тест получения списка пользователей, когда пользователей нет.

     **Для чего нужен:**
     Проверяет, что ручка /api/v1/users корректно возвращает пустой массив, если в базе нет пользователей.

     **Входные данные:**
     - GET-запрос без авторизации и без пользователей в базе.

     **Ожидаемые выходные данные:**
     - HTTP 200 OK
     - Пустой JSON-массив: []
    */
    @Test("List Users - No Users")
    func test_index_noUsers_shouldReturnEmptyArray() async throws {
        try await withApp { app in
            try await app.test(.GET, "api/v1/users", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let users = try res.content.decode([User.Public].self)
                #expect(users.isEmpty)
            })
        }
    }

    /**
     Тест получения списка пользователей, когда пользователь существует.

     **Для чего нужен:**
     Проверяет, что ручка /api/v1/users возвращает массив пользователей, содержащий хотя бы одного пользователя, если таковые есть в базе.

     **Входные данные:**
     - GET-запрос без авторизации.
     - В базе сохранён один пользователь.

     **Ожидаемые выходные данные:**
     - HTTP 200 OK
     - JSON-массив с одним элементом, email совпадает с сохранённым пользователем.
    */
    @Test("List Users - With Users")
    func test_index_withUsers_shouldReturnArray() async throws {
        let user = User(username: "testuser", email: "test@example.com", password: "pass")
        try await withApp { app in
            try await user.save(on: app.db)
            try await app.test(.GET, "api/v1/users", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let users = try res.content.decode([User.Public].self)
                #expect(users.count == 1)
                #expect(users.first?.email == user.email)
            })
        }
    }

    /**
     Тест успешного обновления пользователя по валидному токену.

     **Для чего нужен:**
     Проверяет, что PUT /api/v1/users с валидным токеном обновляет данные пользователя (например, имя) и возвращает новые данные.

     **Входные данные:**
     - PUT-запрос с Bearer Token, соответствующим существующему пользователю.
     - Тело запроса: DTO c новым username.

     **Ожидаемые выходные данные:**
     - HTTP 200 OK
     - JSON public-модель пользователя с обновлённым username.
    */
    @Test("Update User - Success")
    func test_update_withValidToken_shouldUpdateUser() async throws {
        let user = User(username: "oldname", email: "old@mail.com", password: try Bcrypt.hash("123"))
        try await withApp { app in
            try await user.save(on: app.db)
            let token = try Token.generate(for: user)
            try await token.save(on: app.db)

            let updateDTO = UpdateUserDTO(username: "newname", email: nil, password: nil)
            try await app.test(.PUT, "api/v1/users", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token.value)
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
                try req.content.encode(updateDTO)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let updated = try res.content.decode(User.Public.self)
                #expect(updated.username == "newname")
            })
        }
    }

    /**
     Тест попытки обновления пользователя без токена авторизации.

     **Для чего нужен:**
     Проверяет, что PUT /api/v1/users без Bearer Token возвращает ошибку 401 Unauthorized.

     **Входные данные:**
     - PUT-запрос без заголовка Authorization.
     - Тело запроса: любые данные.

     **Ожидаемые выходные данные:**
     - HTTP 401 Unauthorized
    */
    @Test("Update User - No Token")
    func test_update_withoutToken_shouldReturnUnauthorized() async throws {
        let updateDTO = UpdateUserDTO(username: "hacker", email: nil, password: nil)
        try await withApp { app in
            try await app.test(.PUT, "api/v1/users", beforeRequest: { req in
                try req.content.encode(updateDTO)
            }, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            })
        }
    }

    /**
     Тест попытки обновления пользователя с невалидным токеном.

     **Для чего нужен:**
     Проверяет, что PUT /api/v1/users с несуществующим токеном возвращает ошибку 401 Unauthorized.

     **Входные данные:**
     - PUT-запрос с Authorization: Bearer <fake-token>
     - Тело запроса: любые данные.

     **Ожидаемые выходные данные:**
     - HTTP 401 Unauthorized
    */
    @Test("Update User - Invalid Token")
    func test_update_invalidToken_shouldReturnUnauthorized() async throws {
        try await withApp { app in
            let updateDTO = UpdateUserDTO(username: "new", email: nil, password: nil)
            try await app.test(.PUT, "api/v1/users", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: "someInvalidToken")
                try req.content.encode(updateDTO)
            }, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            })
        }
    }
}
