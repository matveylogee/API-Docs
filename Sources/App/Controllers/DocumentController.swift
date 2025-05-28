import Fluent
import Vapor

struct DocumentController: RouteCollection {
    
    func boot(routes: RoutesBuilder) throws {
        // routes here are already protected by Token.guardMiddleware() in `routes(_:)`
        let docs = routes.grouped("api", "v1", "documents")

        // MARK: - Upload document
        // Usage:
        /// Route: POST {base-url}/api/v1/documents
        /// Body: multipart/form-data with fields:
        ///    file: File
        ///    data: {
        ///      fileType: String,
        ///      createTime: String,
        ///      artistName: String,
        ///      artistNickname: String,
        ///      compositionName: String,
        ///      price: String,
        ///      comment?: String,
        ///      isFavorite?: Bool
        ///    }
        // Response:
        /// DocumentDTO
        docs.post { req async throws -> Document.Public in
            /// Authenticate
            let token = try req.auth.require(Token.self)
            let user  = try await token.$user.get(on: req.db)
            let userID = try user.requireID()

            /// Decode multipart
            let file   = try req.content.get(File.self, at: "file")
            let rawJSON = try req.content.get(String.self, at: "data")
            guard let jsonData = rawJSON.data(using: .utf8) else {
                throw Abort(.badRequest, reason: "Invalid JSON in data field")
            }
            let dto = try JSONDecoder().decode(CreateDocumentDTO.self, from: jsonData)

            /// Save file to disk
            let newName  = "\(UUID().uuidString)_\(file.filename)"
            let relPath  = "uploads/" + newName
            let fullPath = req.application.directory.publicDirectory + relPath
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: req.application.directory.publicDirectory + "uploads"),
                withIntermediateDirectories: true
            )
            try Data(buffer: file.data).write(to: URL(fileURLWithPath: fullPath))

            /// Persist to DB
            let document = Document(
                fileName:        file.filename,
                fileURL:         relPath,
                fileType:        dto.fileType,
                createTime:      dto.createTime,
                comment:         dto.comment,
                isFavorite:      dto.isFavorite ?? false,
                artistName:      dto.artistName,
                artistNickname:  dto.artistNickname,
                compositionName: dto.compositionName,
                price:           dto.price
            )
            
            document.$user.id = userID
            try await document.save(on: req.db)
            return document.convertToPublic()
        }

        // MARK: - List documents
        // Usage:
        /// Route: GET {base-url}/api/v1/documents
        // Response:
        /// [DocumentDTO]
        docs.get { req async throws -> [Document.Public] in
            let token = try req.auth.require(Token.self)
            let user  = try await token.$user.get(on: req.db)
            let userID = try user.requireID()

            let list = try await Document.query(on: req.db)
                .filter(\.$user.$id == userID)
                .all()
            return list.map { $0.convertToPublic() }
        }

        // MARK: - Get one document
        // Usage:
        /// Route: GET {base-url}/api/v1/documents/:id
        // Response:
        /// DocumentDTO
        docs.get(":id") { req async throws -> Document.Public in
            let token = try req.auth.require(Token.self)
            let user  = try await token.$user.get(on: req.db)
            let userID = try user.requireID()

            guard
                let id  = req.parameters.get("id", as: UUID.self),
                let doc = try await Document.find(id, on: req.db),
                doc.$user.id == userID
            else {
                throw Abort(.notFound)
            }
            return doc.convertToPublic()
        }

        // MARK: - Download PDF
        // Usage:
        /// Route: GET {base-url}/api/v1/documents/:id/download
        // Response:
        /// application/pdf stream
        docs.get(":id", "download") { req async throws -> Response in
            let token = try req.auth.require(Token.self)
            let user  = try await token.$user.get(on: req.db)
            let userID = try user.requireID()

            guard
                let id  = req.parameters.get("id", as: UUID.self),
                let doc = try await Document.find(id, on: req.db),
                doc.$user.id == userID
            else {
                throw Abort(.notFound)
            }
            let path = req.application.directory.publicDirectory + doc.fileURL
            return req.fileio.streamFile(at: path)
        }

        // MARK: - Delete all documents
        // Usage:
        /// Route: DELETE {base-url}/api/v1/documents
        // Response:
        /// 204 No Content
        docs.delete { req async throws -> HTTPStatus in
            let token = try req.auth.require(Token.self)
            let user  = try await token.$user.get(on: req.db)
            let userID = try user.requireID()

            let userDocs = try await Document.query(on: req.db)
                .filter(\.$user.$id == userID)
                .all()
            for doc in userDocs {
                let fullPath = req.application.directory.publicDirectory + doc.fileURL
                try? FileManager.default.removeItem(atPath: fullPath)
                try await doc.delete(on: req.db)
            }
            return .noContent
        }

        // Grouped by ID for update/delete single document
        docs.group(":id") { group in

            // MARK: - Update comment / favorite
            // Usage:
            /// Route: PUT {base-url}/api/v1/documents/:id
            /// Body: { comment?: String, isFavorite?: Bool }
            // Response:
            /// DocumentDTO
            group.put { req async throws -> Document.Public in
                let token = try req.auth.require(Token.self)
                let user  = try await token.$user.get(on: req.db)
                let userID = try user.requireID()

                let upd = try req.content.decode(UpdateDocumentDTO.self)
                guard
                    let id  = req.parameters.get("id", as: UUID.self),
                    let doc = try await Document.find(id, on: req.db),
                    doc.$user.id == userID
                else {
                    throw Abort(.notFound)
                }
                if let c = upd.comment    { doc.comment = c }
                if let f = upd.isFavorite { doc.isFavorite = f }
                try await doc.update(on: req.db)
                return doc.convertToPublic()
            }

            // MARK: - Delete one document
            // Usage:
            /// Route: DELETE {base-url}/api/v1/documents/:id
            // Response:
            /// 204 No Content
            group.delete { req async throws -> HTTPStatus in
                let token = try req.auth.require(Token.self)
                let user  = try await token.$user.get(on: req.db)
                let userID = try user.requireID()

                guard
                    let id  = req.parameters.get("id", as: UUID.self),
                    let doc = try await Document.find(id, on: req.db),
                    doc.$user.id == userID
                else {
                    throw Abort(.notFound)
                }
                let fullPath = req.application.directory.publicDirectory + doc.fileURL
                try? FileManager.default.removeItem(atPath: fullPath)
                try await doc.delete(on: req.db)
                return .noContent
            }
        }
    }
}
