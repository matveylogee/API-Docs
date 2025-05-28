import XCTest
import Vapor
@testable import App

final class APIKeyServiceTests: XCTestCase {

    // Тест генерации ключа
    func test_generateAPIKey_defaultLength() {
        let service = APIKeyService()
        let key = service.generateAPIKey()
        XCTAssertEqual(key.count, 32, "Длина API-ключа по умолчанию должна быть 32")
        XCTAssertTrue(key.allSatisfy { $0.isLetter || $0.isNumber }, "Ключ должен состоять только из букв и цифр")
    }

    func test_generateAPIKey_customLength() {
        let service = APIKeyService()
        let key = service.generateAPIKey(length: 10)
        XCTAssertEqual(key.count, 10, "Ключ должен быть нужной длины")
    }

    // Тесты с файлом — используем временный путь, чтобы не трогать .env
    func test_save_and_read_APIKey_from_temp_file() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        let service = APIKeyService(filePath: "test_env_file.env")
        let apiKey = "TestSuperSecretKey123"

        // Удалим файл, если вдруг остался от прошлых запусков
        if FileManager.default.fileExists(atPath: service.filePath) {
            try? FileManager.default.removeItem(atPath: service.filePath)
        }

        // Сохраняем ключ
        service.saveAPIKeyToEnvFile(app: app, apiKey: apiKey)

        // Читаем ключ
        let readKey = service.readAPIKeyFromEnvFile(app: app)
        XCTAssertEqual(readKey, apiKey, "Прочитанный ключ должен совпадать с сохранённым")

        // Удаляем файл после теста
        try? FileManager.default.removeItem(atPath: service.filePath)
    }

    func test_readAPIKeyFromEnvFile_fileNotExist_returnsNil() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        let service = APIKeyService(filePath: "not_existing.env")
        // Убедимся, что файл точно не существует
        if FileManager.default.fileExists(atPath: service.filePath) {
            try? FileManager.default.removeItem(atPath: service.filePath)
        }
        let key = service.readAPIKeyFromEnvFile(app: app)
        XCTAssertNil(key, "Если файла нет, должен возвращаться nil")
    }


    func test_saveAPIKeyToEnvFile_doesNotDuplicateKey() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        let service = APIKeyService(filePath: "dedup_env.env")
        let apiKey = "FirstKey123"

        // Удалим файл перед тестом
        if FileManager.default.fileExists(atPath: service.filePath) {
            try FileManager.default.removeItem(atPath: service.filePath)
        }

        // Первый раз сохраняем
        service.saveAPIKeyToEnvFile(app: app, apiKey: apiKey)
        // Второй раз сохраняем — не должно дублироваться
        service.saveAPIKeyToEnvFile(app: app, apiKey: apiKey)
        // Проверяем, что ключ только один
        let contents = try String(contentsOfFile: service.filePath, encoding: .utf8)
        let occurrences = contents.components(separatedBy: "API_KEY=").count - 1
        XCTAssertEqual(occurrences, 1, "Ключ должен встречаться только один раз")

        // Чистим за собой
        try? FileManager.default.removeItem(atPath: service.filePath)
    }
}

