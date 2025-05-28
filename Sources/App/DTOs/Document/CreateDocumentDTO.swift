import Vapor

struct CreateDocumentDTO: Content {
    var fileType: String
    var createTime: String
    var artistName: String
    var artistNickname: String
    var compositionName: String
    var price: String
    var comment: String?
    var isFavorite: Bool?
}
