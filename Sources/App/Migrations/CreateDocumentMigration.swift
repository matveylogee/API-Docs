import Fluent

struct CreateDocumentMigration: AsyncMigration {
    
    let schema = Document.schema
    
    func prepare(on database: any FluentKit.Database) async throws {
        try await database.schema(schema)
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("file_name",        .string,   .required)
            .field("file_url",         .string,   .required)
            .field("file_type",        .string,   .required)
            .field("file_create_time", .string,   .required)
            .field("file_comment",     .string)
            .field("is_favorite",      .bool,     .required, .sql(.default(false)))
            .field("artist_name",      .string,   .required)
            .field("artist_nickname",  .string,   .required)
            .field("composition_name", .string,   .required)
            .field("price",            .string,   .required)
            .create()
    }

    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
}
