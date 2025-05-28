@testable import App
import XCTVapor
import Testing
import Fluent

@Suite("DocumentController Tests", .serialized)
struct DocumentControllerTests {
    
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
    
    // Хелпер для авторизации
    func createUserAndToken(app: Application) async throws -> (User, Token) {
        let user = User(username: "docuser", email: "doc@mail.com", password: try Bcrypt.hash("docpass"))
        try await user.save(on: app.db)
        let token = try Token.generate(for: user)
        try await token.save(on: app.db)
        return (user, token)
    }
    
    // Хелпер (можешь вынести в начало файла)
    func makeMultipartBody(parts: [(name: String, filename: String?, data: Data, contentType: String?)]) -> (body: Data, boundary: String) {
        let boundary = UUID().uuidString
        var body = Data()
        let lineBreak = "\r\n"
        for part in parts {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            if let filename = part.filename {
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\(lineBreak)".data(using: .utf8)!)
            } else {
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"\(lineBreak)".data(using: .utf8)!)
            }
            if let contentType = part.contentType {
                body.append("Content-Type: \(contentType)\(lineBreak)".data(using: .utf8)!)
            }
            body.append(lineBreak.data(using: .utf8)!)
            body.append(part.data)
            body.append(lineBreak.data(using: .utf8)!)
        }
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        return (body, boundary)
    }

    /**
     Тест успешной загрузки документа через multipart/form-data.
     
     **Для чего нужен:**
     Проверяет, что защищённая ручка /api/v1/documents принимает multipart-запрос, корректно сохраняет файл и возвращает public-модель документа.
     
     **Входные данные:**
     - Авторизованный пользователь (Bearer Token)
     - Файл (pdf) в multipart-запросе (поле "file")
     - JSON-строка (поле "data") с метаданными документа
     
     **Ожидаемые выходные данные:**
     - HTTP 200 OK
     - JSON с public-представлением документа (artistName == "Artist" и т.п.)
    */
    @Test("Upload Document - Success")
    func test_uploadDocument_shouldSucceed() async throws {
        try await withApp { app in
            let (user, token) = try await createUserAndToken(app: app)
            let dto = CreateDocumentDTO(
                fileType: "pdf",
                createTime: "2024-01-01T12:00:00",
                artistName: "Artist",
                artistNickname: "Nick",
                compositionName: "Comp",
                price: "100",
                comment: "Test comment",
                isFavorite: false
            )
            let jsonData = try JSONEncoder().encode(dto)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            let fileData = Data("Fake PDF".utf8)
            
            let (body, boundary) = makeMultipartBody(parts: [
                (name: "file", filename: "test.pdf", data: fileData, contentType: "application/pdf"),
                (name: "data", filename: nil, data: Data(jsonString.utf8), contentType: "application/json")
            ])

            try await app.test(.POST, "api/v1/documents", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token.value)
                if let apiKey = apiService.readAPIKeyFromEnvFile(app: app) {
                    req.headers.add(name: "x-api-key", value: apiKey)
                }
                req.headers.contentType = HTTPMediaType(type: "multipart", subType: "form-data", parameters: ["boundary": boundary])
                req.body = .init(data: body)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let doc = try res.content.decode(Document.Public.self)
                #expect(doc.artistName == "Artist")
            })
        }
    }

    /**
     Тест получения списка документов пользователя.
     
     **Для чего нужен:**
     Проверяет, что /api/v1/documents возвращает все документы, связанные с авторизованным пользователем.
     
     **Входные данные:**
     - Авторизованный пользователь (Bearer Token)
     - В базе заранее сохранён хотя бы один документ для пользователя
     
     **Ожидаемые выходные данные:**
     - HTTP 200 OK
     - JSON-массив public-документов, первый документ содержит ожидаемые поля (artistName == "Artist")
    */
    @Test("List Documents - Success")
    func test_listDocuments_shouldReturnArray() async throws {
        try await withApp { app in
            let (user, token) = try await createUserAndToken(app: app)
            // Добавим документ вручную
            let doc = Document(
                fileName: "file.pdf",
                fileURL: "uploads/file.pdf",
                fileType: "pdf",
                createTime: "2024-01-01T00:00:00",
                comment: "C",
                isFavorite: false,
                artistName: "Artist",
                artistNickname: "Nick",
                compositionName: "Name",
                price: "99"
            )
            doc.$user.id = try user.requireID()
            try await doc.save(on: app.db)
            try await app.test(.GET, "api/v1/documents", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token.value)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let docs = try res.content.decode([Document.Public].self)
                #expect(!docs.isEmpty)
                #expect(docs[0].artistName == "Artist")
            })
        }
    }

    /**
     Тест запроса несуществующего документа.
     
     **Для чего нужен:**
     Проверяет, что при попытке получить документ по несуществующему UUID сервер возвращает ошибку 404 Not Found.
     
     **Входные данные:**
     - Авторизованный пользователь (Bearer Token)
     - Случайный UUID, не связанный ни с одним документом в базе

     **Ожидаемые выходные данные:**
     - HTTP 404 Not Found
    */
    @Test("Get Document - Not Found")
    func test_getDocument_notFound_shouldReturn404() async throws {
        try await withApp { app in
            let (_, token) = try await createUserAndToken(app: app)
            try await app.test(.GET, "api/v1/documents/\(UUID())", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token.value)
            }, afterResponse: { res async throws in
                #expect(res.status == .notFound)
            })
        }
    }

    /**
     Тест обновления комментария к документу.
     
     **Для чего нужен:**
     Проверяет, что PUT /api/v1/documents/:id успешно обновляет только указанные поля (например, comment) и возвращает актуальные данные документа.
     
     **Входные данные:**
     - Авторизованный пользователь (Bearer Token)
     - Документ, уже существующий в базе
     - Запрос с новым comment (в DTO)

     **Ожидаемые выходные данные:**
     - HTTP 200 OK
     - JSON public-документа, поле comment обновлено
    */
    @Test("Update Document - Comment")
    func test_updateDocument_comment_shouldSucceed() async throws {
        try await withApp { app in
            let (user, token) = try await createUserAndToken(app: app)
            let doc = Document(
                fileName: "update.pdf",
                fileURL: "uploads/update.pdf",
                fileType: "pdf",
                createTime: "2024-01-01T00:00:00",
                comment: "old",
                isFavorite: false,
                artistName: "A", artistNickname: "N", compositionName: "C", price: "1"
            )
            doc.$user.id = try user.requireID()
            try await doc.save(on: app.db)
            
            let updateDTO = UpdateDocumentDTO(comment: "new comment", isFavorite: nil)
            try await app.test(.PUT, "api/v1/documents/\(try doc.requireID())", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token.value)
                try req.content.encode(updateDTO)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let updated = try res.content.decode(Document.Public.self)
                #expect(updated.comment == "new comment")
            })
        }
    }

    /**
     Тест удаления одного документа.

     **Для чего нужен:**
     Проверяет, что DELETE /api/v1/documents/:id удаляет указанный документ пользователя и возвращает статус 204.

     **Входные данные:**
     - Авторизованный пользователь (Bearer Token)
     - Существующий документ пользователя (id)

     **Ожидаемые выходные данные:**
     - HTTP 204 No Content
    */
    @Test("Delete Document - Success")
    func test_deleteDocument_shouldReturnNoContent() async throws {
        try await withApp { app in
            let (user, token) = try await createUserAndToken(app: app)
            let doc = Document(
                fileName: "del.pdf",
                fileURL: "uploads/del.pdf",
                fileType: "pdf",
                createTime: "2024-01-01T00:00:00",
                comment: nil,
                isFavorite: false,
                artistName: "A", artistNickname: "N", compositionName: "C", price: "1"
            )
            doc.$user.id = try user.requireID()
            try await doc.save(on: app.db)

            try await app.test(.DELETE, "api/v1/documents/\(try doc.requireID())", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token.value)
            }, afterResponse: { res async throws in
                #expect(res.status == .noContent)
            })
        }
    }

    /**
     Тест удаления всех документов пользователя.

     **Для чего нужен:**
     Проверяет, что DELETE /api/v1/documents удаляет все документы, принадлежащие пользователю, и возвращает статус 204. После удаления документов в базе не остаётся.

     **Входные данные:**
     - Авторизованный пользователь (Bearer Token)
     - В базе есть хотя бы один документ пользователя

     **Ожидаемые выходные данные:**
     - HTTP 204 No Content
     - В базе после запроса документов больше нет
    */
    @Test("Delete All Documents - Success")
    func test_deleteAllDocuments_shouldReturnNoContent() async throws {
        try await withApp { app in
            let (user, token) = try await createUserAndToken(app: app)
            let doc = Document(
                fileName: "delall.pdf",
                fileURL: "uploads/delall.pdf",
                fileType: "pdf",
                createTime: "2024-01-01T00:00:00",
                comment: nil,
                isFavorite: false,
                artistName: "A", 
                artistNickname: "N",
                compositionName: "C",
                price: "1"
            )
            doc.$user.id = try user.requireID()
            try await doc.save(on: app.db)

            try await app.test(.DELETE, "api/v1/documents", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token.value)
            }, afterResponse: { res async throws in
                #expect(res.status == .noContent)
                // Доп проверка, что документов больше нет
                let docs = try await Document.query(on: app.db).all()
                #expect(docs.isEmpty)
            })
        }
    }
}
