import Fluent
import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: AuthController())
    try app.register(collection: UsersController())

    let protected = app.grouped(Token.authenticator(), Token.guardMiddleware())
    try protected.register(collection: DocumentController())
}
