import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import CoreHaptics // Ensure CoreHaptics is imported, though UIImpactFeedbackGenerator is in UIKit
import UIKit // Added for UIPasteboard
import Foundation

// MARK: - Network and Authentication Classes

struct User: Codable {
    let id: String
    let username: String
    let email: String
    let settings: UserSettings?
    
    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case username, email, settings
    }
}

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var errorMessage: String?
    
    private let baseURL = "http://localhost:5002"
    private let keychain = Keychain()
    
    init() {
        loadAuthToken()
    }
    
    private func loadAuthToken() {
        if let token = keychain.get("auth_token"), !token.isEmpty {
            isAuthenticated = true
            // Optionally verify token and load user info
            Task {
                await fetchUserInfo()
            }
        }
    }
    
    func login(emailOrUsername: String, password: String) async -> Bool {
        let url = URL(string: "\(baseURL)/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "email": emailOrUsername,
            "password": password
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let token = json["token"] as? String {
                        await MainActor.run {
                            keychain.set(token, forKey: "auth_token")
                            isAuthenticated = true
                            errorMessage = nil
                        }
                        await fetchUserInfo()
                        return true
                    }
                } else {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? String {
                        await MainActor.run {
                            errorMessage = error
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Network error: \(error.localizedDescription)"
            }
        }
        
        return false
    }
    
    func createAccount(username: String, email: String, password: String, activationCode: String) async -> Bool {
        let url = URL(string: "\(baseURL)/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "username": username,
            "email": email,
            "password": password,
            "activation_code": activationCode
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 201 {
                    await MainActor.run {
                        errorMessage = nil
                    }
                    return true
                } else {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? String {
                        await MainActor.run {
                            errorMessage = error
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Network error: \(error.localizedDescription)"
            }
        }
        
        return false
    }
    
    func resetPassword(email: String, activationCode: String, newPassword: String) async -> Bool {
        let url = URL(string: "\(baseURL)/reset-password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "email": email,
            "activation_code": activationCode,
            "new_password": newPassword
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    await MainActor.run {
                        errorMessage = nil
                    }
                    return true
                } else {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? String {
                        await MainActor.run {
                            errorMessage = error
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Network error: \(error.localizedDescription)"
            }
        }
        
        return false
    }
    
    func logout() {
        Task {
            if let token = keychain.get("auth_token") {
                let url = URL(string: "\(baseURL)/logout")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                do {
                    let (_, _) = try await URLSession.shared.data(for: request)
                } catch {
                    print("Logout request failed: \(error)")
                }
            }
            
            await MainActor.run {
                keychain.delete("auth_token")
                isAuthenticated = false
                currentUser = nil
                errorMessage = nil
            }
        }
    }
    
    private func fetchUserInfo() async {
        guard let token = keychain.get("auth_token") else { return }
        
        let url = URL(string: "\(baseURL)/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let user = try JSONDecoder().decode(User.self, from: data)
                    await MainActor.run {
                        currentUser = user
                    }
                } else {
                    await MainActor.run {
                        isAuthenticated = false
                        keychain.delete("auth_token")
                    }
                }
            }
        } catch {
            print("Failed to fetch user info: \(error)")
            await MainActor.run {
                isAuthenticated = false
                keychain.delete("auth_token")
            }
        }
    }
}

class VoiceAPIManager: ObservableObject {
    private let authManager: AuthManager
    private let baseURL = "http://localhost:5002"
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }
    
    func generateAudioWithClonedVoice(topic: String, value: String) async throws -> Data {
        guard let token = Keychain().get("auth_token") else {
            throw APIError.notAuthenticated
        }
        
        let url = URL(string: "\(baseURL)/generate-audio-cloned")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "topic": topic,
            "value": value
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                return data
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    throw APIError.serverError(error)
                } else {
                    throw APIError.serverError("Unknown server error")
                }
            }
        }
        
        throw APIError.networkError
    }
}

enum APIError: Error {
    case notAuthenticated
    case networkError
    case serverError(String)
    
    var localizedDescription: String {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .networkError:
            return "Network error"
        case .serverError(let message):
            return message
        }
    }
}

class Keychain {
    func set(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
    
    func get(_ key: String) -> String? {
        return UserDefaults.standard.string(forKey: key)
    }
    
    func delete(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Helper Types for JSON Decoding

// Helper to decode mixed-type JSON values
struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode value"))
        }
    }
}

// MARK: - Global Enums and Structs (Accessible throughout the file)

// MODIFIED: Add Codable conformance
enum Language: String, Codable, CaseIterable, Identifiable {
    case english = "english"
    case spanish = "spanish"
    // Add other languages as needed

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .spanish:
            return "Español"
        // Add other display names
        }
    }
}

// MODIFIED: UserSettings struct to explicitly implement Codable and add memberwise initializer
struct UserSettings: Codable, Equatable {
    var language: Language
    var voiceSimilarity: Double
    var stability: Double
    var addBackgroundSound: Bool
    var backgroundVolume: Double
    var voiceIds: [String]?

    enum CodingKeys: String, CodingKey {
        case language
        case voiceSimilarity = "voice_similarity"
        case stability
        case addBackgroundSound = "add_background_sound"
        case backgroundVolume = "background_volume"
        case voiceIds = "voice_ids"
    }

    // Explicit Decodable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decode(Language.self, forKey: .language)
        voiceSimilarity = try container.decode(Double.self, forKey: .voiceSimilarity)
        stability = try container.decode(Double.self, forKey: .stability)
        addBackgroundSound = try container.decode(Bool.self, forKey: .addBackgroundSound)
        backgroundVolume = try container.decode(Double.self, forKey: .backgroundVolume)
        voiceIds = try container.decodeIfPresent([String].self, forKey: .voiceIds)
    }

    // Explicit Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language, forKey: .language)
        try container.encode(voiceSimilarity, forKey: .voiceSimilarity)
        try container.encode(stability, forKey: .stability)
        try container.encode(addBackgroundSound, forKey: .addBackgroundSound)
        try container.encode(backgroundVolume, forKey: .backgroundVolume)
        try container.encodeIfPresent(voiceIds, forKey: .voiceIds)
    }
    
    // Memberwise initializer (needed because providing init(from:) removes the synthesized one)
    init(language: Language, voiceSimilarity: Double, stability: Double, addBackgroundSound: Bool, backgroundVolume: Double, voiceIds: [String]? = nil) {
        self.language = language
        self.voiceSimilarity = voiceSimilarity
        self.stability = stability
        self.addBackgroundSound = addBackgroundSound
        self.backgroundVolume = backgroundVolume
        self.voiceIds = voiceIds
    }

    static var defaultSettings: UserSettings {
        UserSettings(
            language: .english,
            voiceSimilarity: 0.85,
            stability: 0.70,
            addBackgroundSound: true,
            backgroundVolume: 0.5,
            voiceIds: []
        )
    }
}

// Payload for updating settings
struct UserSettingsPayload: Codable {
    let language: String
    let voiceSimilarity: Double
    let stability: Double
    let addBackgroundSound: Bool // NEW
    let backgroundVolume: Double   // NEW
    // voice_ids are not directly updated via this payload, managed by voice cloning flow

    enum CodingKeys: String, CodingKey {
        case language
        case voiceSimilarity = "voice_similarity"
        case stability
        case addBackgroundSound = "add_background_sound" // NEW
        case backgroundVolume = "background_volume"     // NEW
    }
}

// MARK: - AppScreen Enum

enum AppScreen {
    case buttonSelection
    case textInput
    case cardInput
    case numberInput
    case starSignInput
    case voiceMemos
    case editScreen
    case home // Added home screen case
    case tutorial // Added tutorial screen case
    case createAccount // Added for user registration
    case login // Added for user login
    case forgotPassword // Added for forgot password functionality
}

// MARK: - ContentView

struct ContentView: View {
    @State private var selectedButton: String = ""
    @State private var inputText: String = ""
    @State private var currentScreen: AppScreen = .createAccount // Start with createAccount
    @State private var generatedRecording: RecordingData? = nil
    // @StateObject private var apiManager = VoiceAPIManager() // OLD
    // @StateObject private var authManager = AuthManager() // OLD

    @StateObject private var authManager: AuthManager
    @StateObject private var apiManager: VoiceAPIManager
    
    @State private var generationError: String? = nil // Added for error display

    @MainActor // ADDED @MainActor
    init() {
        let authManagerInstance = AuthManager()
        _authManager = StateObject(wrappedValue: authManagerInstance)
        // Pass the same AuthManager instance to VoiceAPIManager
        _apiManager = StateObject(wrappedValue: VoiceAPIManager(authManager: authManagerInstance))
    }
    
    var body: some View {
        ZStack { // Added ZStack for potential global loading/error overlay
            switch currentScreen {
            case .createAccount:
                CreateAccountView(authManager: authManager, onAccountCreated: {
                    // After account creation, maybe go to login or directly to home
                    currentScreen = .login 
                }, onGoToLogin: {
                    currentScreen = .login
                })
            case .login:
                LoginView(authManager: authManager, onLoggedIn: {
                    currentScreen = .home // Navigate to home after login
                }, onGoToCreateAccount: {
                    currentScreen = .createAccount
                }, onForgotPassword: {
                    currentScreen = .forgotPassword // Navigate to forgot password screen
                })
            case .forgotPassword:
                ForgotPasswordView(authManager: authManager, onPasswordReset: {
                    currentScreen = .login // Navigate back to login after successful reset
                }, onBackToLogin: {
                    currentScreen = .login // Navigate back to login
                })
            case .buttonSelection:
                ButtonSelectionView(selectedButton: $selectedButton, onButtonSelected: { screen in
                    currentScreen = screen
                }, onBackTapped: {
                    currentScreen = .home
                })
            case .textInput:
                TextInputView(inputText: $inputText, onTextEntered: {
                    // Instead of direct navigation, call generation function
                    generateAudioFromInputs()
                }, onBackTapped: {
                    currentScreen = .buttonSelection
                })
            case .cardInput:
                CardInputView(selectedCard: $inputText, onCardSelected: {
                    generateAudioFromInputs()
                }, onBackTapped: {
                    currentScreen = .buttonSelection
                })
            case .numberInput:
                NumberInputView(selectedNumber: $inputText, onNumberSelected: {
                    generateAudioFromInputs()
                }, onBackTapped: {
                    currentScreen = .buttonSelection
                })
            case .starSignInput:
                StarSignInputView(selectedSign: $inputText, onSignSelected: {
                    generateAudioFromInputs()
                }, onBackTapped: {
                    currentScreen = .buttonSelection
                })
            case .voiceMemos:
                VoiceMemosView(
                    selectedButton: selectedButton,
                    inputText: inputText,
                    generatedRecording: generatedRecording,
                    onEditTapped: {
                        // currentScreen = .editScreen // OLD
                        currentScreen = .home       // NEW: Navigate to Home
                    }
                )
            case .editScreen:
                NavigationView {
                    EditScreenView(
                        apiManager: apiManager,
                        onBackTapped: { // MODIFIED: No longer receives RecordingData
                            // OLD:
                            // if let newRecordingFromEditScreen = newRecordingFromEditScreen {
                            //     // Log that audio was generated but is not directly used in the main flow from here
                            //     print("ContentView: EditScreenView returned with new recording: \\(newRecordingFromEditScreen.title), duration: \\(newRecordingFromEditScreen.duration). This is not used when returning to Home from Settings.")
                            // }
                            currentScreen = .home // New: Always return to home
                        }
                    )
                }
            case .home: // Handle home screen
                if authManager.isAuthenticated { // Use isAuthenticated instead of authToken check
                    NavigationView { // Added NavigationView
                        HomeScreenView(
                            authManager: authManager, // Pass authManager to HomeScreenView
                            onPerformTapped: {
                                // Reset flow-specific states for a fresh "Perform" flow
                                self.selectedButton = ""
                                self.inputText = ""
                                self.generatedRecording = nil 
                                currentScreen = .buttonSelection
                            },
                            onSettingsTapped: {
                                currentScreen = .editScreen
                            },
                            onTutorialTapped: {
                                currentScreen = .tutorial
                            },
                            onSignOutTapped: {
                                // authManager.logout() is called within HomeScreenView's button action
                                currentScreen = .login // Navigate to login screen
                            }
                        )
                        Spacer()
                        }
                } else {
                    // If not logged in, redirect to login or create account
                    // This is a fallback, ideally currentScreen should be managed correctly
                    LoginView(authManager: authManager, onLoggedIn: {
                        currentScreen = .home
                    }, onGoToCreateAccount: {
                        currentScreen = .createAccount
                    }, onForgotPassword: {
                        currentScreen = .forgotPassword
                    })
                }
            case .tutorial: // Handle tutorial screen
                NavigationView { // Added NavigationView
                    TutorialView {
                        currentScreen = .home // Action to go back to home screen
                    }
                }
            }

            if let error = generationError { // Global error display
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button("OK") {
                        generationError = nil
                    }
                    .padding(.top)
                }
                .padding()
                .background(Color.red.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(10)
                .frame(maxWidth: 300)
                .transition(.opacity)
            }
        }
        .onAppear {
            // AuthManager's init() already loads the token from Keychain
            if authManager.isAuthenticated {
                currentScreen = .home
            } else {
                currentScreen = .login // Show login if not authenticated
            }
        }
    }

    // Helper function to format date (copied from VoiceMemosView/EditScreenView)
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // Helper function to estimate duration (copied from EditScreenView)
    private func estimateDuration(from audioData: Data) -> String {
        do {
            let player = try AVAudioPlayer(data: audioData)
            let seconds = Int(player.duration) // Ensure seconds is Int
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        } catch {
            // Assuming 16kHz, 16-bit mono audio, so 16000 bytes/second for 8-bit, or 32000 for 16-bit.
            // Let's adjust if this is mono 16-bit, which is common.
            // If it's 16-bit (2 bytes per sample) and mono (1 channel) at 16kHz:
            // Bytes per second = 16000 samples/sec * 1 channel * 2 bytes/sample = 32000 bytes/sec
            // If the backend provides 16kHz mono PCM s16le, then this should be audioData.count / 32000
            // For now, let's assume the previous 16000 was a placeholder or for 8-bit.
            // To be safer, if we don't know the format, this estimation is very rough.
            // Let's use a more standard estimate for 16-bit mono audio at 16kHz
            let bytesPerSecondEstimate = 32000 // 16000 samples/sec * 2 bytes/sample (for 16-bit mono)
            let estimatedSeconds = audioData.count / bytesPerSecondEstimate // This will be Int
            return "\(estimatedSeconds / 60):\(String(format: "%02d", estimatedSeconds % 60))"
        }
    }

    func generateAudioFromInputs() {
        guard !selectedButton.isEmpty, !inputText.isEmpty else {
            // If inputs are not valid, just navigate without generation
            currentScreen = .voiceMemos
            return
        }

        // isLoadingAudio = true // Removed
        generationError = nil // Clear previous errors

        let pendingRecordingID = UUID() // Create a unique ID for this recording upfront
        let placeholderTitle = "Strange Dream"
        
        // Calculate yesterday's date
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        
        // Create and set a placeholder recording immediately
        let placeholderRecording = RecordingData(
            id: pendingRecordingID,
            title: placeholderTitle,
            date: formattedDate(yesterday), // Use yesterday's date
            duration: "--:--"
        )
        self.generatedRecording = placeholderRecording

        // Navigate to VoiceMemosView immediately
        currentScreen = .voiceMemos
        print("ContentView: Navigated to VoiceMemosView, starting audio generation in background.")

        Task {
            do {
                print("ContentView: Starting audio generation with topic: \(selectedButton), value: \(inputText)")
                let audioData = try await apiManager.generateAudioWithClonedVoice(
                    topic: selectedButton,
                    value: inputText
                )
                
                let finalRecording = RecordingData(
                    id: pendingRecordingID, // Use the same ID
                    title: "Strange Dream",
                    date: formattedDate(yesterday), // Use yesterday's date
                    duration: estimateDuration(from: audioData),
                    audioData: audioData
                )
                
                await MainActor.run {
                    self.generatedRecording = finalRecording // Update the recording
                    // isLoadingAudio = false // Removed
                    print("ContentView: Audio generation successful, recording updated.")
                    
                    // Haptic feedback for success
                    let generator = UIImpactFeedbackGenerator(style: .heavy) // Changed to .heavy
                    generator.impactOccurred()
                    
                    print("ContentView: Successfully generated audio. Navigating to VoiceMemosView.")
                }
            } catch {
                await MainActor.run {
                    // isLoadingAudio = false // Removed
                    let errorMsg = "Failed: \(error.localizedDescription)"
                    self.generationError = errorMsg
                    print("ContentView: Error generating audio: \(errorMsg)")
                    
                    // Optionally, update the placeholder to show an error state
                    let errorRecording = RecordingData(
                        id: pendingRecordingID, // Use the same ID
                        title: "Error: \(selectedButton) - \(inputText.prefix(20))...",
                        date: formattedDate(yesterday), // Use yesterday's date
                        duration: "Error"
                    )
                    self.generatedRecording = errorRecording
                }
            }
        }
    }
}

struct HomeScreenView: View {
    @ObservedObject var authManager: AuthManager // Added AuthManager
    let onPerformTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onTutorialTapped: () -> Void
    let onSignOutTapped: () -> Void // Added for sign-out

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Section
                    VStack(spacing: 16) {
                        // Welcome message
                        VStack(spacing: 8) {
                            Text("Good \(timeOfDay)")
                                .font(.system(size: 32, weight: .light, design: .default))
                                .foregroundColor(.white.opacity(0.9))
                            
                            if let username = authManager.currentUser?.username {
                                Text(username.capitalized)
                                    .font(.system(size: 40, weight: .bold, design: .default))
                                    .foregroundColor(.white)
                            } else {
                                Text("Welcome")
                                    .font(.system(size: 40, weight: .bold, design: .default))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.top, 60)
                        
                        // Subtitle
                        Text("Visions by Alex Latorre and Nicolas Rosales")
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    // Main Action Section
                    VStack(spacing: 24) {
                        // Primary Perform Button
                        Button(action: onPerformTapped) {
                            HStack(spacing: 16) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.white)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Perform")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.white)
                                    
                                    Text("Perform the routine")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.48, blue: 1.0), // iOS Blue
                                        Color(red: 0.0, green: 0.38, blue: 0.9)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 0.1), value: 1.0)
                        
                        // Conditional Bluetooth Routine Button (only for alexlatorre)
                        if authManager.currentUser?.username == "alexlatorre" {
                            Button(action: {
                                // Placeholder action for Bluetooth Routine
                                print("Bluetooth Routine tapped")
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(.black)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Bluetooth Routine")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.black)
                                        
                                        Text("Connect and configure devices")
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(.black.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.8))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 20)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color.yellow,
                                            Color.yellow.opacity(0.8)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.yellow.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .scaleEffect(1.0)
                            .animation(.easeInOut(duration: 0.1), value: 1.0)
                        }
                        
                        // Secondary Actions Grid
                        HStack(spacing: 16) {
                            // Settings Button
                            Button(action: onSettingsTapped) {
                                VStack(spacing: 12) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Text("Settings")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                            }
                            
                            // Tutorial Button
                            Button(action: onTutorialTapped) {
                                VStack(spacing: 12) {
                                    Image(systemName: "book.fill")
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Text("Tutorial")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    // Bottom Section
                    VStack(spacing: 16) {
                        // Sign Out Button
                        Button(action: {
                            print("🔥 Sign Out button tapped!")
                            authManager.logout()
                            print("🔥 About to call onSignOutTapped()")
                            onSignOutTapped()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.red)
                                
                                Text("Sign Out")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        
                        // App version info
                        Text("Visions • Version 1.0")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
        }
    }
    
    // Helper computed property for time-based greeting
    private var timeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<22:
            return "Evening"
        default:
            return "Evening"
        }
    }
}


struct TutorialView: View {
    let onBackTapped: () -> Void
    @State private var currentPage = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Premium gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBlue).opacity(0.1),
                        Color(.systemPurple).opacity(0.05),
                        Color(.systemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header Section
                        VStack(spacing: 16) {
                            // App Icon with glow effect
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(.systemBlue).opacity(0.2),
                                                Color(.systemPurple).opacity(0.1)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 40, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(.systemBlue),
                                                Color(.systemPurple)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            VStack(spacing: 8) {
                                Text("Visions")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                Text("Transform your ideas into intelligent voice memos")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 20)
                        
                        // Features Overview Cards
                        VStack(spacing: 16) {
                            FeatureCard(
                                icon: "brain.head.profile",
                                iconColor: Color(.systemBlue),
                                title: "AI-Powered Generation",
                                description: "Create voice memos on any topic using advanced AI technology"
                            )
                            
                            FeatureCard(
                                icon: "person.wave.2.fill",
                                iconColor: Color(.systemPurple),
                                title: "Voice Cloning",
                                description: "Use your own voice or choose from premium AI voices"
                            )
                            
                            FeatureCard(
                                icon: "text.bubble.fill",
                                iconColor: Color(.systemGreen),
                                title: "Smart Content",
                                description: "Generate contextual content for cards, movies, stories, and more"
                            )
                        }
                        
                        // How it Works Section
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(Color(.systemYellow))
                                
                                Text("How It Works")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 24)
                            
                            VStack(spacing: 16) {
                                StepCard(
                                    number: 1,
                                    title: "Choose Your Topic",
                                    description: "Select from categories like Cards, Movies, Numbers, or create custom content",
                                    icon: "square.grid.2x2.fill"
                                )
                                
                                StepCard(
                                    number: 2,
                                    title: "Enter Your Ideas",
                                    description: "Provide specific details or let AI generate content for you",
                                    icon: "text.cursor"
                                )
                                
                                StepCard(
                                    number: 3,
                                    title: "AI Magic Happens",
                                    description: "Advanced AI creates a natural-sounding voice memo tailored to your needs",
                                    icon: "sparkles"
                                )
                                
                                StepCard(
                                    number: 4,
                                    title: "Listen & Enjoy",
                                    description: "Your personalized voice memo appears in your recordings list",
                                    icon: "play.circle.fill"
                                )
                            }
                        }
                        
                        // Tips Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(Color(.systemOrange))
                                
                                Text("Pro Tips")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 24)
                            
                            VStack(spacing: 12) {
                                TipCard(
                                    icon: "mic.fill",
                                    text: "Record your voice in Settings to create personalized AI clones"
                                )
                                
                                TipCard(
                                    icon: "wand.and.stars",
                                    text: "Try different topics to discover the AI's creative capabilities"
                                )
                                
                                TipCard(
                                    icon: "headphones",
                                    text: "Use headphones for the best audio experience"
                                )
                            }
                        }
                        
                        // Get Started Button
                        Button(action: onBackTapped) {
                            HStack(spacing: 12) {
                                Text("Get Started")
                                    .font(.system(size: 18, weight: .semibold))
                                
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 18))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(.systemBlue),
                                        Color(.systemPurple)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                    }
                    .padding(.bottom, 100)
                }
            }
        }
    }
}

struct TextInputView: View {
    @Binding var inputText: String
    let onTextEntered: () -> Void
    let onBackTapped: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Modern gradient background matching app theme
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Back Button - Fixed at top left
                HStack {
                    Button(action: onBackTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Header Section
                VStack(spacing: 16) {
                    Text("Custom Input")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Enter your custom text or idea")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                Spacer()
                
                // Text Input Section
                VStack(spacing: 24) {
                    // Custom styled text field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Text")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        
                        ZStack(alignment: .topLeading) {
                            // Background
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                            
                            // Text Editor for multiline input
                            TextField("Enter your text here...", text: $inputText)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.white)
                                .padding(16)
                                .focused($isTextFieldFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        onTextEntered()
                                    }
                                }
                        }
                        .frame(minHeight: 120)
                    }
                    
                    // Generate Button
                    Button(action: {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onTextEntered()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 18, weight: .medium))
                            
                            Text("Generate Voice Memo")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(.systemBlue),
                                    Color(.systemPurple)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Helper Text
                Text("Enter any topic, story, or idea you'd like converted to audio")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Focus immediately when view appears
            isTextFieldFocused = true
        }
        .onTapGesture {
            // Keep keyboard focused - don't dismiss on tap
            if !isTextFieldFocused {
                isTextFieldFocused = true
            }
        }
    }
}



// MARK: - Specialized Input Views

// Card Input View
struct CardInputView: View {
    @Binding var selectedCard: String
    let onCardSelected: () -> Void
    let onBackTapped: () -> Void
    
    let cardValues = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
    let suits = ["♠", "♥", "♦", "♣"]
    
    @State private var selectedValue: String = ""
    @State private var selectedSuit: String = ""
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Back Button - Fixed at top left
                HStack {
                    Button(action: onBackTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Header Section
                VStack(spacing: 16) {
                    Text("Select a Card")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Choose a card value and suit")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 40)
                
                // Card Values Section
                VStack(spacing: 16) {
                    Text("Card Value")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(cardValues, id: \.self) { value in
                            Button(action: {
                                selectedValue = value
                                updateSelectedCard()
                            }) {
                                Text(value)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(selectedValue == value ? .black : .white)
                                    .frame(width: 60, height: 60)
                                    .background(selectedValue == value ? Color.white : Color.white.opacity(0.2))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                
                // Suits Section
                VStack(spacing: 16) {
                    Text("Suit")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 20) {
                        ForEach(suits, id: \.self) { suit in
                            Button(action: {
                                selectedSuit = suit
                                updateSelectedCard()
                            }) {
                                Text(suit)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(selectedSuit == suit ? .black : .white)
                                    .frame(width: 70, height: 70)
                                    .background(selectedSuit == suit ? Color.white : Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                
                // Selected Card Display
                if !selectedValue.isEmpty && !selectedSuit.isEmpty {
                    VStack(spacing: 12) {
                        Text("Selected Card")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("\(selectedValue)\(selectedSuit)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(16)
                    }
                }
                
                Spacer()
                
                // Generate Button
                if !selectedValue.isEmpty && !selectedSuit.isEmpty {
                    Button(action: onCardSelected) {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 18, weight: .medium))
                            
                            Text("Generate Voice Memo")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(.systemBlue),
                                    Color(.systemPurple)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 32)
                }
                
                Spacer()
            }
        }
    }
    
    private func updateSelectedCard() {
        if !selectedValue.isEmpty && !selectedSuit.isEmpty {
            selectedCard = "\(selectedValue) of \(getSuitName(selectedSuit))"
        }
    }
    
    private func getSuitColor(_ suit: String) -> Color {
        switch suit {
        case "♥", "♦":
            return .red
        case "♠", "♣":
            return .white
        default:
            return .white
        }
    }
    
    private func getSuitName(_ suit: String) -> String {
        switch suit {
        case "♠":
            return "Spades"
        case "♥":
            return "Hearts"
        case "♦":
            return "Diamonds"
        case "♣":
            return "Clubs"
        default:
            return ""
        }
    }
}

// Number Input View
struct NumberInputView: View {
    @Binding var selectedNumber: String
    let onNumberSelected: () -> Void
    let onBackTapped: () -> Void
    
    @State private var tensDigit: String = ""
    @State private var onesDigit: String = ""
    
    let digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Back Button - Fixed at top left
                HStack {
                    Button(action: onBackTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Header Section
                VStack(spacing: 16) {
                    Text("Select a Number")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Choose a two-digit number (00-99)")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 40)
                
                // Tens Digit Section
                VStack(spacing: 16) {
                    Text("Tens Digit")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(digits, id: \.self) { digit in
                            Button(action: {
                                tensDigit = digit
                                updateSelectedNumber()
                            }) {
                                Text(digit)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(tensDigit == digit ? .black : .white)
                                    .frame(width: 50, height: 50)
                                    .background(tensDigit == digit ? Color.white : Color.white.opacity(0.2))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                
                // Ones Digit Section
                VStack(spacing: 16) {
                    Text("Ones Digit")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(digits, id: \.self) { digit in
                            Button(action: {
                                onesDigit = digit
                                updateSelectedNumber()
                            }) {
                                Text(digit)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(onesDigit == digit ? .black : .white)
                                    .frame(width: 50, height: 50)
                                    .background(onesDigit == digit ? Color.white : Color.white.opacity(0.2))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                
                // Selected Number Display
                if !tensDigit.isEmpty && !onesDigit.isEmpty {
                    VStack(spacing: 12) {
                        Text("Selected Number")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("\(tensDigit)\(onesDigit)")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 20)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(16)
                    }
                }
                
                Spacer()
                
                // Generate Button
                if !tensDigit.isEmpty && !onesDigit.isEmpty {
                    Button(action: onNumberSelected) {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 18, weight: .medium))
                            
                            Text("Generate Voice Memo")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(.systemBlue),
                                    Color(.systemPurple)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 32)
                }
                
                Spacer()
            }
        }
    }
    
    private func updateSelectedNumber() {
        if !tensDigit.isEmpty && !onesDigit.isEmpty {
            selectedNumber = "\(tensDigit)\(onesDigit)"
        }
    }
}

// Star Sign Input View
struct StarSignInputView: View {
    @Binding var selectedSign: String
    let onSignSelected: () -> Void
    let onBackTapped: () -> Void
    
    let starSigns = [
        ("♈", "Aries"), ("♉", "Taurus"), ("♊", "Gemini"),
        ("♋", "Cancer"), ("♌", "Leo"), ("♍", "Virgo"),
        ("♎", "Libra"), ("♏", "Scorpio"), ("♐", "Sagittarius"),
        ("♑", "Capricorn"), ("♒", "Aquarius"), ("♓", "Pisces")
    ]
    
    @State private var selectedSignName: String = ""
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Back Button - Fixed at top left
                HStack {
                    Button(action: onBackTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Header Section
                VStack(spacing: 16) {
                    Text("Select a Star Sign")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Choose your zodiac sign")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 40)
                
                // Star Signs Grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(starSigns, id: \.1) { sign in
                        Button(action: {
                            selectedSignName = sign.1
                            selectedSign = sign.1
                        }) {
                            VStack(spacing: 8) {
                                Text(sign.0)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(selectedSignName == sign.1 ? .black : .white)
                                
                                Text(sign.1)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(selectedSignName == sign.1 ? .black : .white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 90)
                            .background(selectedSignName == sign.1 ? Color.white : Color.white.opacity(0.1))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 32)
                
                // Selected Sign Display
                if !selectedSignName.isEmpty {
                    VStack(spacing: 12) {
                        Text("Selected Sign")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        let selectedSignData = starSigns.first { $0.1 == selectedSignName }
                        if let signData = selectedSignData {
                            HStack(spacing: 16) {
                                Text(signData.0)
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text(signData.1)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 20)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(16)
                        }
                    }
                }
                
                Spacer()
                
                // Generate Button
                if !selectedSignName.isEmpty {
                    Button(action: onSignSelected) {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 18, weight: .medium))
                            
                            Text("Generate Voice Memo")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(.systemBlue),
                                    Color(.systemPurple)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 32)
                }
                
                Spacer()
            }
        }
    }
}

// Enhanced RecordingData struct to handle both file-based and data-based recordings
struct RecordingData: Identifiable, Equatable {
    let id: UUID // Changed: id is now a let constant, will be initialized
    let title: String
    let date: String
    let duration: String
    var audioData: Data? = nil
    
    // Added initializer to control ID
    init(id: UUID = UUID(), title: String, date: String, duration: String, audioData: Data? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.duration = duration
        self.audioData = audioData
    }
    
    static func == (lhs: RecordingData, rhs: RecordingData) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.date == rhs.date &&
               lhs.duration == rhs.duration &&
               lhs.audioData == rhs.audioData // Data is Equatable
    }
}

struct VoiceMemosView: View {
    let selectedButton: String
    let inputText: String
    let generatedRecording: RecordingData?
    let onEditTapped: () -> Void
    
    @State private var showingPeek = false
    @State private var showingSiriPrompt = false
    @State private var selectedRecording: RecordingData? = nil
    @State private var isPlaying = false
    @State private var currentTime = 0.0
    @State private var totalTime = 15.0
    @State private var audioPlayer: AVAudioPlayer? = nil
    
    // Added helper function
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var recordings: [RecordingData] {
        var result = [
            RecordingData(title: "Carrer dels Ametllers, 9 24", date: "18 May 2025", duration: "0:15"),
            RecordingData(title: "2024-14-04", date: "14 Apr 2024", duration: "0:12"),
            RecordingData(title: "Strange Dream 01", date: "2 Apr 2024", duration: "0:09"),
            RecordingData(title: "Dream 11", date: "21 Mar 2024", duration: "0:07"),
            RecordingData(title: "Dream 10", date: "8 Mar 2024", duration: "0:31"),
            RecordingData(title: "Strange Dream 02", date: "22 Feb 2024", duration: "0:30"),
            RecordingData(title: "Dream 09", date: "10 Feb 2024", duration: "0:27"),
            // Generate a static array of
            RecordingData(title: "Strange Dream 03", date: "15 Jan 2024", duration: "0:11"),
            RecordingData(title: "Dream 07", date: "2 Jan 2024", duration: "0:04"),
            RecordingData(title: "Dream 06", date: "19 Dec 2023", duration: "0:09"),
            RecordingData(title: "Dream 05", date: "7 Dec 2023", duration: "0:22"),
            RecordingData(title: "Strange Dream 04", date: "23 Nov 2023", duration: "0:21"),
            RecordingData(title: "Dream 04", date: "10 Nov 2023", duration: "0:02"),
            RecordingData(title: "Dream 03", date: "29 Oct 2023", duration: "0:31"),
            RecordingData(title: "Strange Dream 05", date: "14 Oct 2023", duration: "0:09"),
            RecordingData(title: "Dream 02", date: "2 Oct 2023", duration: "0:24"),
            RecordingData(title: "Dream 01", date: "20 Sep 2023", duration: "0:44"),
            RecordingData(title: "Strange Dream 06", date: "8 Sep 2023", duration: "1:31"),
            RecordingData(title: "2023-08-25", date: "25 Aug 2023", duration: "2:22"),
            RecordingData(title: "2023-08-13", date: "13 Aug 2023", duration: "0:57"),
            RecordingData(title: "2023-07-31", date: "31 Jul 2023", duration: "0:11"),
            RecordingData(title: "2023-07-17", date: "17 Jul 2023", duration: "0:26"),
            RecordingData(title: "2023-07-03", date: "3 Jul 2023", duration: "0:24"),
            RecordingData(title: "2023-06-18", date: "18 Jun 2023",duration: "0:12"),
            RecordingData(title: "2023-06-05", date: "5 Jun 2023", duration: "0:15")
        ]
        
        // Insert the generated recording at the beginning if available
        if let generatedRecording = generatedRecording {
            result.insert(generatedRecording, at: 0)
        }
        
        return result
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 20) {
                    
                    Spacer()
                    
                    // Navigation Header
                    HStack {
                        Button(action: {}) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        Button("Edit") {
                            onEditTapped()
                        }
                        .font(.system(size: 17))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Title with selected button and input text info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("All Recordings")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Siri Prompt
                    if showingSiriPrompt {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                            
                            Text("Say \"\"")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Button(action: {
                                showingSiriPrompt = false
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    
                    // Recordings List
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(recordings.indices, id: \.self) { index in
                                VStack(spacing: 0) {
                                    RecordingRow(
                                        recording: recordings[index],
                                        isSelected: selectedRecording?.id == recordings[index].id,
                                        isPlaying: isPlaying,
                                        currentTime: currentTime,
                                        totalTime: totalTime,
                                        onTap: { recording in
                                            if selectedRecording?.id == recording.id {
                                                selectedRecording = nil
                                                stopPlayback()
                                            } else {
                                                selectedRecording = recording
                                                totalTime = parseDuration(recording.duration)
                                                currentTime = 0
                                                isPlaying = false
                                                
                                                // Prepare audio player if we have audio data
                                                if let audioData = recording.audioData {
                                                    prepareAudioPlayer(with: audioData)
                                                }
                                            }
                                        },
                                        onPlay: {
                                            togglePlayback(for: recordings[index])
                                        },
                                        onDelete: {
                                            selectedRecording = nil
                                            stopPlayback()
                                        }
                                    )
                                    
                                    // Add separator line between recordings, but not after the last one
                                    if index < recordings.count - 1 {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(height: 0.5)
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 20)
                    
                    Spacer()
                    
                    // Record Button
                    VStack(spacing: 30) {
                        Button(action: {}) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 64, height: 64)
                            }
                        }
                        .scaleEffect(showingPeek ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: showingPeek)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !showingPeek {
                                        showingPeek = true
                                    }
                                }
                                .onEnded { _ in
                                    showingPeek = false
                                }
                        )
                    }
                    .padding(.bottom, 50)
                }
                .background(Color.black)
                .ignoresSafeArea()
                
                // Peek Visualization Overlay
                if showingPeek {
                    PeekVisualizationView(selectedButton: selectedButton, inputText: inputText)
                        .transition(.opacity.combined(with: .scale))
                        .animation(.easeInOut(duration: 0.2), value: showingPeek)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func prepareAudioPlayer(with data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            if let duration = audioPlayer?.duration {
                totalTime = duration
            }
        } catch {
            print("Error creating audio player: \(error.localizedDescription)")
        }
    }
    
    private func togglePlayback(for recording: RecordingData) {
        // If we have audio data for this recording, use it
        if let audioData = recording.audioData {
            if audioPlayer == nil {
                prepareAudioPlayer(with: audioData)
            }
            
            if isPlaying {
                audioPlayer?.pause()
                isPlaying = false
            } else {
                do {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                } catch {
                    print("VoiceMemosView: Failed to override output port to speaker: \(error.localizedDescription)")
                }
                audioPlayer?.play()
                isPlaying = true
                
                // Start a timer to update the progress
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    if let player = audioPlayer, player.isPlaying {
                        currentTime = player.currentTime
                    } else {
                        timer.invalidate()
                        if currentTime >= totalTime {
                            isPlaying = false
                            currentTime = 0
                        }
                    }
                }
            }
        } else {
            // Fall back to the original simulation for recordings without audio data
            togglePlaybackSimulation()
        }
    }
    
    private func togglePlaybackSimulation() {
        isPlaying.toggle()
        if isPlaying {
            // Simulate playback progress
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                if isPlaying && currentTime < totalTime {
                    currentTime += 0.1
                } else {
                    timer.invalidate()
                    if currentTime >= totalTime {
                        isPlaying = false
                        currentTime = 0
                    }
                }
            }
        }
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
    }
    
    private func parseDuration(_ duration: String) -> Double {
        let components = duration.split(separator: ":")
        if components.count == 2 {
            let minutes = Double(components[0]) ?? 0
            let seconds = Double(components[1]) ?? 0
            return minutes * 60 + seconds
        }
        return 0
    }
}


// MARK: - Authentication Views

struct CreateAccountView: View {
    @ObservedObject var authManager: AuthManager
    let onAccountCreated: () -> Void
    let onGoToLogin: () -> Void

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var activationCode = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @FocusState private var focusedField: CreateAccountField?
    
    enum CreateAccountField: Hashable {
        case username, email, password, activationCode
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Premium gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBlue).opacity(0.8),
                        Color(.systemPurple).opacity(0.6),
                        Color(.systemIndigo).opacity(0.9)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: 40)
                        
                        // Header Section
                        VStack(spacing: 20) {
                            // App Icon
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 100, height: 100)
                                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                                
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 50, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.white, .white.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            VStack(spacing: 8) {
                                Text("Join Visions")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                
                                Text("Create your account to start generating intelligent voice memos")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Form Section
                        VStack(spacing: 20) {
                            // Username Field
                            AuthTextField(
                                title: "Username",
                                text: $username,
                                icon: "person.fill",
                                keyboardType: .default,
                                isSecure: false
                            )
                            .focused($focusedField, equals: .username)
                            
                            // Email Field
                            AuthTextField(
                                title: "Email",
                                text: $email,
                                icon: "envelope.fill",
                                keyboardType: .emailAddress,
                                isSecure: false
                            )
                            .focused($focusedField, equals: .email)
                            
                            // Password Field
                            AuthTextField(
                                title: "Password",
                                text: $password,
                                icon: "lock.fill",
                                keyboardType: .default,
                                isSecure: true
                            )
                            .focused($focusedField, equals: .password)
                            
                            // Activation Code Field
                            AuthTextField(
                                title: "Activation Code",
                                text: $activationCode,
                                icon: "key.fill",
                                keyboardType: .default,
                                isSecure: false
                            )
                            .focused($focusedField, equals: .activationCode)
                            
                            // Error Message
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.red)
                                }
                                .padding(16)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Action Buttons
                        VStack(spacing: 16) {
                            // Create Account Button
                            Button(action: createAccount) {
                                HStack(spacing: 12) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Create Account")
                                            .font(.system(size: 18, weight: .semibold))
                                        
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 18))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(.ultraThickMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            }
                            .disabled(isLoading || username.isEmpty || email.isEmpty || password.isEmpty || activationCode.isEmpty)
                            .opacity((isLoading || username.isEmpty || email.isEmpty || password.isEmpty || activationCode.isEmpty) ? 0.6 : 1.0)
                            
                            // Login Link
                            Button(action: onGoToLogin) {
                                HStack(spacing: 8) {
                                    Text("Already have an account?")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Text("Sign In")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onTapGesture {
            focusedField = nil
        }
    }

    func createAccount() {
        isLoading = true
        errorMessage = nil
        focusedField = nil
        
        Task {
            let success = await authManager.createAccount(
                username: username,
                email: email,
                password: password,
                activationCode: activationCode
            )
            await MainActor.run {
                isLoading = false
                if success {
                    onAccountCreated()
                } else {
                    errorMessage = authManager.errorMessage ?? "Failed to create account."
                }
            }
        }
    }
}

struct LoginView: View {
    @ObservedObject var authManager: AuthManager
    let onLoggedIn: () -> Void
    let onGoToCreateAccount: () -> Void
    let onForgotPassword: () -> Void

    @State private var emailOrUsername = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @FocusState private var focusedField: LoginField?
    
    enum LoginField: Hashable {
        case emailOrUsername, password
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Premium gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemGreen).opacity(0.8),
                        Color(.systemBlue).opacity(0.7),
                        Color(.systemTeal).opacity(0.9)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: 60)
                        
                        // Header Section
                        VStack(spacing: 20) {
                            // App Icon
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 100, height: 100)
                                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                                
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 50, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.white, .white.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            VStack(spacing: 8) {
                                Text("Welcome Back")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Sign in to access your voice memos")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Form Section
                        VStack(spacing: 20) {
                            // Email/Username Field
                            AuthTextField(
                                title: "Username or Email",
                                text: $emailOrUsername,
                                icon: "person.circle.fill",
                                keyboardType: .emailAddress,
                                isSecure: false
                            )
                            .focused($focusedField, equals: .emailOrUsername)
                            
                            // Password Field
                            AuthTextField(
                                title: "Password",
                                text: $password,
                                icon: "lock.fill",
                                keyboardType: .default,
                                isSecure: true
                            )
                            .focused($focusedField, equals: .password)
                            
                            // Error Message
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.red)
                                }
                                .padding(16)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Action Buttons
                        VStack(spacing: 16) {
                            // Sign In Button
                            Button(action: login) {
                                HStack(spacing: 12) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Sign In")
                                            .font(.system(size: 18, weight: .semibold))
                                        
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 18))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(.ultraThickMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            }
                            .disabled(isLoading || emailOrUsername.isEmpty || password.isEmpty)
                            .opacity((isLoading || emailOrUsername.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                            
                            // Forgot Password Link
                            Button(action: onForgotPassword) {
                                Text("Forgot Password?")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .underline()
                            }
                            
                            // Create Account Link
                            Button(action: onGoToCreateAccount) {
                                HStack(spacing: 8) {
                                    Text("Don't have an account?")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Text("Create One")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer(minLength: 60)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onTapGesture {
            focusedField = nil
        }
    }

    func login() {
        isLoading = true
        errorMessage = nil
        focusedField = nil
        
        Task {
            let success = await authManager.login(emailOrUsername: emailOrUsername, password: password)
            await MainActor.run {
                isLoading = false
                if success {
                    onLoggedIn()
                } else {
                    errorMessage = authManager.errorMessage ?? "Login failed."
                }
            }
        }
    }
}

// MARK: - Forgot Password View

struct ForgotPasswordView: View {
    @ObservedObject var authManager: AuthManager
    let onPasswordReset: () -> Void
    let onBackToLogin: () -> Void

    @State private var email = ""
    @State private var activationCode = ""
    @State private var newPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showSuccessMessage = false
    @FocusState private var focusedField: ForgotPasswordField?
    
    enum ForgotPasswordField: Hashable {
        case email, activationCode, newPassword
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Premium gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemOrange).opacity(0.8),
                        Color(.systemRed).opacity(0.7),
                        Color(.systemPink).opacity(0.9)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: 60)
                        
                        // Header Section
                        VStack(spacing: 20) {
                            // Reset Icon
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 100, height: 100)
                                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                                
                                Image(systemName: "key.horizontal.fill")
                                    .font(.system(size: 50, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.white, .white.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            VStack(spacing: 8) {
                                Text("Reset Password")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Enter your email and activation code to reset your password")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Form Section
                        VStack(spacing: 20) {
                            // Email Field
                            AuthTextField(
                                title: "Email",
                                text: $email,
                                icon: "envelope.fill",
                                keyboardType: .emailAddress,
                                isSecure: false
                            )
                            .focused($focusedField, equals: .email)
                            
                            // Activation Code Field
                            AuthTextField(
                                title: "Activation Code",
                                text: $activationCode,
                                icon: "key.fill",
                                keyboardType: .default,
                                isSecure: false
                            )
                            .focused($focusedField, equals: .activationCode)
                            
                            // New Password Field
                            AuthTextField(
                                title: "New Password",
                                text: $newPassword,
                                icon: "lock.fill",
                                keyboardType: .default,
                                isSecure: true
                            )
                            .focused($focusedField, equals: .newPassword)
                            
                            // Error Message
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.red)
                                }
                                .padding(16)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                            // Success Message
                            if showSuccessMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Password reset successfully! You can now sign in with your new password.")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.green)
                                }
                                .padding(16)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Action Buttons
                        VStack(spacing: 16) {
                            // Reset Password Button
                            Button(action: resetPassword) {
                                HStack(spacing: 12) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Reset Password")
                                            .font(.system(size: 18, weight: .semibold))
                                        
                                        Image(systemName: "key.horizontal.fill")
                                            .font(.system(size: 18))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(.ultraThickMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            }
                            .disabled(isLoading || email.isEmpty || activationCode.isEmpty || newPassword.isEmpty || showSuccessMessage)
                            .opacity((isLoading || email.isEmpty || activationCode.isEmpty || newPassword.isEmpty || showSuccessMessage) ? 0.6 : 1.0)
                            
                            // Back to Login Button
                            Button(action: onBackToLogin) {
                                HStack(spacing: 8) {
                                    Text("Remember your password?")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Text("Sign In")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer(minLength: 60)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onTapGesture {
            focusedField = nil
        }
    }

    func resetPassword() {
        isLoading = true
        errorMessage = nil
        focusedField = nil
        
        Task {
            let success = await authManager.resetPassword(email: email, activationCode: activationCode, newPassword: newPassword)
            await MainActor.run {
                isLoading = false
                if success {
                    showSuccessMessage = true
                    // Auto-navigate to login after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        onPasswordReset()
                    }
                } else {
                    errorMessage = authManager.errorMessage ?? "Password reset failed."
                }
            }
        }
    }
}

// MARK: - Auth Components

struct AuthTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .padding(.leading, 16)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 24)
                
                Group {
                    if isSecure {
                        SecureField("Enter \(title.lowercased())", text: $text)
                    } else {
                        TextField("Enter \(title.lowercased())", text: $text)
                    }
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Supporting Views

struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

struct StepCard: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(.systemBlue).opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Text("\(number)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(.systemBlue))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Color(.systemBlue))
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

struct TipCard: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color(.systemOrange))
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Button Selection View

struct ButtonSelectionView: View {
    @Binding var selectedButton: String
    let onButtonSelected: (AppScreen) -> Void
    let onBackTapped: () -> Void
    
    // Keypad data: (number_value, display_text, category_name, letters)
    private let keypadMapping: [(Int, String, String?, String)] = [
        (2, "2", "Movies", "ABC"),
        (3, "3", "Card", "DEF"),
        (4, "4", "Numbers", "GHI"),
        (5, "5", "Star Signs", "JKL"),
        (6, "6", "Custom", "MNO"),
        (7, "7", nil, "PQRS"),
        (8, "8", nil, "TUV"),
        (9, "9", nil, "WXYZ")
    ]
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onBackTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                Spacer()
                
                // Keypad
                VStack(spacing: 30) {
                    // Row 1: 2, 3, 4
                    HStack(spacing: 25) {
                        ForEach(0..<3, id: \.self) { index in
                            let (number, numberText, category, letters) = keypadMapping[index]
                            
                            Button(action: {
                                if let category = category {
                                    selectedButton = category
                                    switch category {
                                    case "Movies":
                                        onButtonSelected(.textInput)
                                    case "Card":
                                        onButtonSelected(.cardInput)
                                    case "Numbers":
                                        onButtonSelected(.numberInput)
                                    case "Star Signs":
                                        onButtonSelected(.starSignInput)
                                    case "Custom":
                                        onButtonSelected(.textInput)
                                    default:
                                        onButtonSelected(.textInput)
                                    }
                                }
                            }) {
                                VStack(spacing: -2) {
                                    Text(numberText)
                                        .font(.system(size: 36, weight: .light))
                                        .foregroundColor(.white)
                                    
                                    if !letters.isEmpty {
                                        Text(letters)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.white)
                                            .tracking(1.5)
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                )
                            }
                        }
                    }
                    
                    // Row 2: 5, 6, 7
                    HStack(spacing: 25) {
                        ForEach(3..<6, id: \.self) { index in
                            let (number, numberText, category, letters) = keypadMapping[index]
                            
                            Button(action: {
                                if let category = category {
                                    selectedButton = category
                                    switch category {
                                    case "Movies":
                                        onButtonSelected(.textInput)
                                    case "Card":
                                        onButtonSelected(.cardInput)
                                    case "Numbers":
                                        onButtonSelected(.numberInput)
                                    case "Star Signs":
                                        onButtonSelected(.starSignInput)
                                    case "Custom":
                                        onButtonSelected(.textInput)
                                    default:
                                        onButtonSelected(.textInput)
                                    }
                                }
                            }) {
                                VStack(spacing: -2) {
                                    Text(numberText)
                                        .font(.system(size: 36, weight: .light))
                                        .foregroundColor(.white)
                                    
                                    if !letters.isEmpty {
                                        Text(letters)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.white)
                                            .tracking(1.5)
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                )
                            }
                        }
                    }
                    
                    // Row 3: 8, 9
                    HStack(spacing: 25) {
                        ForEach(6..<8, id: \.self) { index in
                            let (number, numberText, category, letters) = keypadMapping[index]
                            
                            Button(action: {}) {
                                VStack(spacing: -2) {
                                    Text(numberText)
                                        .font(.system(size: 36, weight: .light))
                                        .foregroundColor(.white)
                                    
                                    if !letters.isEmpty {
                                        Text(letters)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.white)
                                            .tracking(1.5)
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                )
                            }
                        }
                        
                        // Empty space for alignment
                        Spacer()
                            .frame(width: 80, height: 80)
                    }
                }
                
                Spacer()
            }
        }
    }
}

// MARK: - Recording Related Views

struct RecordingRow: View {
    let recording: RecordingData
    let isSelected: Bool
    let isPlaying: Bool
    let currentTime: Double
    let totalTime: Double
    let onTap: (RecordingData) -> Void
    let onPlay: () -> Void
    let onDelete: () -> Void
    
    private var progress: Double {
        guard totalTime > 0 else { return 0 }
        return min(currentTime / totalTime, 1.0)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recording.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(recording.date)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray)
                        
                        Text("•")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray)
                        
                        Text(recording.duration)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Button(action: onPlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.clear)
            .onTapGesture {
                onTap(recording)
            }
            
            // Progress bar (only shown when selected)
            if isSelected {
                VStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 2)
                            
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * progress, height: 2)
                        }
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 20)
                    
                    // Time labels
                    HStack {
                        Text(timeString(from: currentTime))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text(timeString(from: totalTime))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)
            }
        }
    }
    
    private func timeString(from seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct PeekVisualizationView: View {
    let selectedButton: String
    let inputText: String
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Peek Preview")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 8) {
                Text("Topic: \(selectedButton)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Input: \(inputText)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
        }
        .padding(32)
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
        .padding(40)
    }
}

// MARK: - Edit Screen View

struct EditScreenView: View {
    @ObservedObject var apiManager: VoiceAPIManager
    let onBackTapped: () -> Void
    
    var body: some View {
        VStack {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding()
            
            Spacer()
            
            Button("Back to Home") {
                onBackTapped()
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.blue)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationBarHidden(true)
    }
}

