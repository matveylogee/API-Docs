import Fluent
import Vapor

final class Document: Model, Content, @unchecked Sendable {
    
    static let schema = Schema.documents.rawValue

    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "file_name")
    var fileName: String
    
    @Field(key: "file_url")
    var fileURL: String
    
    @Field(key: "file_type")
    var fileType: String
    
    @Field(key: "file_create_time")
    var createTime: String
    
    @Field(key: "file_comment")
    var comment: String?
    
    @Field(key: "is_favorite")
    var isFavorite: Bool
    
    @Field(key: "artist_name")
    var artistName: String
    
    @Field(key: "artist_nickname")
    var artistNickname: String
    
    @Field(key: "composition_name")
    var compositionName: String
    
    @Field(key: "price")
    var price: String

    init() { }

    init(id: UUID? = nil,
         fileName: String,
         fileURL: String,
         fileType: String,
         createTime: String,
         comment: String? = nil,
         isFavorite: Bool = false,
         artistName: String,
         artistNickname: String,
         compositionName: String,
         price: String)
    {
        self.id               = id
        self.fileName         = fileName
        self.fileURL          = fileURL
        self.fileType         = fileType
        self.createTime       = createTime
        self.comment          = comment
        self.isFavorite       = isFavorite
        self.artistName       = artistName
        self.artistNickname   = artistNickname
        self.compositionName  = compositionName
        self.price            = price
    }
}

extension Document {
    struct Public: Content {
        var id: UUID?
        var fileName: String
        var fileURL: String
        var fileType: String
        var createTime: String
        
        var comment: String?
        var isFavorite: Bool

        var artistName: String
        var artistNickname: String
        var compositionName: String
        var price: String
    }

    func convertToPublic() -> Public {
        .init(
            id: id,
            fileName: fileName,
            fileURL: fileURL,
            fileType: fileType,
            createTime: createTime,
            comment: comment,
            isFavorite: isFavorite,
            artistName: artistName,
            artistNickname: artistNickname,
            compositionName: compositionName,
            price: price
        )
    }
}
