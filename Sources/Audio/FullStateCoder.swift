import Foundation

enum FullStateCoder {
    enum CoderError: Error, Equatable {
        case archiveFailed
        case unarchiveFailed
        case unexpectedType
    }

    private static let allowedClasses: [AnyClass] = [
        NSDictionary.self,
        NSArray.self,
        NSString.self,
        NSNumber.self,
        NSData.self,
    ]

    static func encode(_ fullState: [String: Any]?) throws -> Data? {
        guard let fullState else {
            return nil
        }

        do {
            return try NSKeyedArchiver.archivedData(withRootObject: fullState as NSDictionary, requiringSecureCoding: true)
        } catch {
            throw CoderError.archiveFailed
        }
    }

    static func decode(_ data: Data?) throws -> [String: Any]? {
        guard let data else {
            return nil
        }

        do {
            let object = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data)
            guard let dictionary = object as? [String: Any] else {
                throw CoderError.unexpectedType
            }
            return dictionary
        } catch let error as CoderError {
            throw error
        } catch {
            throw CoderError.unarchiveFailed
        }
    }
}
