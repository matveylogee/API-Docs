import Vapor

struct DocumentDTO: Content {
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

extension Document {
    func convertToDTO() -> DocumentDTO {
        .init(
            id:               id,
            fileName:         fileName,
            fileURL:          fileURL,
            fileType:         fileType,
            createTime:       createTime,
            comment:          comment,
            isFavorite:       isFavorite,
            artistName:       artistName,
            artistNickname:   artistNickname,
            compositionName:  compositionName,
            price:            price
        )
    }
}
