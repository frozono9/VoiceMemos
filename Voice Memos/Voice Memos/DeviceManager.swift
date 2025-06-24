import Foundation
import UIKit
import Security
import CryptoKit

/// Manager para obtener y manejar el identificador único del dispositivo
/// Este identificador se mantiene persistente en el Keychain para que sea el mismo
/// incluso después de reinstalar la app
class DeviceManager {
    
    private static let keychainService = "com.yourapp.VoiceMemosAI.device"
    private static let keychainAccount = "deviceIdentifier"
    
    /// Obtiene el identificador único del dispositivo
    /// Si no existe, lo genera y lo guarda en el Keychain
    static func getDeviceId() -> String {
        // Primero intentar obtener del Keychain
        if let existingDeviceId = getDeviceIdFromKeychain() {
            print("DeviceManager: Using existing device ID from Keychain: \(existingDeviceId)")
            return existingDeviceId
        }
        
        // Si no existe, generar uno nuevo
        let newDeviceId = generateNewDeviceId()
        saveDeviceIdToKeychain(deviceId: newDeviceId)
        print("DeviceManager: Generated new device ID: \(newDeviceId)")
        return newDeviceId
    }
    
    /// Genera un nuevo identificador único del dispositivo
    private static func generateNewDeviceId() -> String {
        // Combinar información del dispositivo para crear un ID único
        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion
        let uuid = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        
        // Crear un string único basado en el dispositivo y un UUID
        let combinedString = "\(deviceModel)-\(systemVersion)-\(uuid)-\(timestamp)"
        
        // Crear un hash del string para tener un ID más corto y consistente
        let deviceId = combinedString.sha256()
        
        return deviceId
    }
    
    /// Obtiene el device ID del Keychain
    private static func getDeviceIdFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let retrievedData = dataTypeRef as? Data,
               let deviceId = String(data: retrievedData, encoding: .utf8) {
                return deviceId
            }
        }
        
        return nil
    }
    
    /// Guarda el device ID en el Keychain
    private static func saveDeviceIdToKeychain(deviceId: String) {
        guard let data = deviceId.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Eliminar cualquier elemento existente primero
        SecItemDelete(query as CFDictionary)
        
        // Agregar el nuevo elemento
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("DeviceManager: Error saving device ID to keychain: \(status)")
        } else {
            print("DeviceManager: Device ID saved to keychain successfully")
        }
    }
    
    /// Método para limpiar el device ID (útil para testing o reset completo)
    static func clearDeviceId() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            print("DeviceManager: Device ID cleared from keychain")
        } else if status == errSecItemNotFound {
            print("DeviceManager: No device ID found to clear")
        } else {
            print("DeviceManager: Error clearing device ID: \(status)")
        }
    }
}
// MARK: - String Extension para SHA256
extension String {
    func sha256() -> String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Alternative simpler implementation
extension DeviceManager {
    /// Implementación alternativa más simple sin hash complejo
    static func generateSimpleDeviceId() -> String {
        let uuid = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        let deviceModel = UIDevice.current.model.replacingOccurrences(of: " ", with: "-")
        
        return "\(deviceModel)-\(timestamp)-\(uuid.prefix(8))"
    }
}
