import Vapor

struct UpdateDocumentDTO: Content {
    var comment: String?
    var isFavorite: Bool?
}
