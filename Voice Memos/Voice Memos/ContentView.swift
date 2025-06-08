import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import CoreHaptics // Ensure CoreHaptics is imported, though UIImpactFeedbackGenerator is in UIKit
import UIKit // Added for UIPasteboard

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

    enum AppScreen {
        case buttonSelection
        case textInput
        case voiceMemos
        case editScreen
        case home // Added home screen case
        case tutorial // Added tutorial screen case
        case createAccount // Added for user registration
        case login // Added for user login
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
                })
            case .buttonSelection:
                ButtonSelectionView(selectedButton: $selectedButton, onButtonSelected: {
                    currentScreen = .textInput
                }, onBackTapped: {
                    currentScreen = .home
                })
            case .textInput:
                TextInputView(inputText: $inputText) {
                    // Instead of direct navigation, call generation function
                    generateAudioFromInputs()
                }
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
                        Text("Create AI-powered voice memos")
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
                            authManager.logout()
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
                        Text("Voice Memos AI • Version 1.0")
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
                                Text("Voice Memos AI")
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
                                    .font(.system(size: 18, weight: .medium))
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
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color(.systemBlue).opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationTitle("Tutorial")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    onBackTapped()
                }
                .font(.system(size: 17, weight: .medium))
            }
        }
    }
}

// MARK: - Tutorial Support Views

struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct StepCard: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Step number with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(.systemBlue),
                                Color(.systemPurple)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Text("\(number)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            };                VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(.systemBlue))
                    
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
    }
}

struct TipCard: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(.systemOrange))
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ButtonSelectionView: View {
    @Binding var selectedButton: String
    let onButtonSelected: () -> Void
    let onBackTapped: () -> Void
    
    let buttonTitles = [
        "Cards", "Numbers", "Phobias", "Years",
        "Names", "Star Signs", "Movies", "Custom"
    ]
    
    var body: some View {
        ZStack {
            Image("backgroundImage") // Replace "backgroundImage" with your image name
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 2), spacing: 20) {
                    ForEach(Array(buttonTitles.enumerated()), id: \.offset) { index, title in
                        Button(action: {
                            selectedButton = title
                            onButtonSelected()
                        }) {
                            Text(title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                        }
                        .frame(height: 120)
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Back button at bottom right
                HStack {
                    Spacer()
                    Button(action: onBackTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.clear)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.clear)
                        .cornerRadius(25)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

struct TextInputView: View {
    @Binding var inputText: String
    let onTextEntered: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        ZStack {
            Image("backgroundImage") // Replace "backgroundImage" with your image name
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea(.all, edges: .all)
            
            VStack(spacing: 30) {
                Spacer()
                
                TextField("Enter text here...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 18))
                    .padding(.horizontal, 20)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        onTextEntered()
                    }
                
                Spacer()
            }
        }
        .onAppear {
            isTextFieldFocused = true
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


// MARK: - Models
struct VoiceGenerationRequest {
    let audioData: Data
    let text: String
    let stability: Double
    let similarityBoost: Double
    let addBackground: Bool
    let backgroundVolume: Double
}

struct ThoughtRequest {
    let topic: String
    let value: String
}

// MARK: - Network Manager
@MainActor // Add @MainActor here
class VoiceAPIManager: ObservableObject {
    @Published var apiKeyVerified: Bool? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var generatedAudioURL: URL? = nil
    @Published var connectionStatus: ConnectionStatus = .unknown // Added this line
    
    // Settings properties - ensure these match UserSettings
    @Published var language: Language = UserSettings.defaultSettings.language 
    @Published var stability: Double = UserSettings.defaultSettings.stability
    @Published var similarityBoost: Double = UserSettings.defaultSettings.voiceSimilarity // Name consistency
    @Published var addBackground: Bool = UserSettings.defaultSettings.addBackgroundSound // NEW
    @Published var backgroundVolume: Double = UserSettings.defaultSettings.backgroundVolume // NEW

    let baseURL = "https://voicememos-production.up.railway.app" // MODIFIED: Use Railway deployment URL
    private var fallbackURLs: [String] = [] // Removed fallback to 0.0.0.0 for now
    private let apiKey = "test_api_key" // Replace with your actual API key if needed
    let authManager: AuthManager // Add AuthManager instance

    enum ConnectionStatus {
        case unknown
        case connected
        case failed
    }
    
    // Add an initializer to accept AuthManager
    init(authManager: AuthManager) { // NEW - authManager is now required
        self.authManager = authManager
        // Initialize settings from current user if available
        loadSettingsFromAuth()
    }

    // MARK: - Public API Methods
    
    func verifyAPIKey() async throws -> Bool {
        // Try the primary URL first
        do {
            let result = try await verifyAPIWithURL(baseURL)
            self.connectionStatus = .connected
            return result
        } catch {
            print("Primary URL failed: \(error.localizedDescription)")
            
            for fallbackURL in fallbackURLs {
                print("Primary URL failed, trying fallback: \(fallbackURL)")
                do {
                    let result = try await verifyAPIWithURL(fallbackURL)
                    self.connectionStatus = .connected
                    return result
                } catch {
                    print("Fallback URL \(fallbackURL) failed: \(error.localizedDescription)")
                }
            }
            
            self.connectionStatus = .failed
            throw NetworkError.connectionFailed
        }
    }
    
    private func verifyAPIWithURL(_ urlString: String) async throws -> Bool {
        guard let url = URL(string: "\(urlString)/verify-api") else {
            print("VoiceAPIManager: Invalid URL for API verification: \(urlString)/verify-api")
            throw NetworkError.invalidURL
        }
        
        print("Attempting to verify API at: \(url.absoluteString)")
        
        // Create a URLRequest to have more control over the request
        var request = URLRequest(url: url)
        request.timeoutInterval = 10 // Set a reasonable timeout
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            print("API verification response: \(httpResponse.statusCode)")
            return httpResponse.statusCode == 200
        } catch {
            print("API verification error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func generateThought(topic: String, value: String) async throws -> String {
        // Try primary URL first
        do {
            return try await generateThoughtWithURL(baseURL, topic: topic, value: value)
        } catch let error as NetworkError where error.isAuthError {
            print("VoiceAPIManager: Authentication error during thought generation: \(error.localizedDescription)")
            throw error // Re-throw auth errors directly
        }
        catch {
            print("Primary URL failed for thought generation: \(error.localizedDescription)")
            
            // Try fallbacks
            for fallbackURL in fallbackURLs {
                do {
                    return try await generateThoughtWithURL(fallbackURL, topic: topic, value: value)
                } catch let error as NetworkError where error.isAuthError {
                     print("VoiceAPIManager: Authentication error during thought generation on fallback: \(error.localizedDescription)")
                     throw error // Re-throw auth errors directly
                }
                catch {
                    print("Fallback URL \(fallbackURL) failed for thought generation: \(error.localizedDescription)")
                }
            }
            // If all URLs fail, throw the error
            throw error
        }
    }
    
    private func generateThoughtWithURL(_ urlString: String, topic: String, value: String) async throws -> String {
        guard let encodedTopic = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(urlString)/generate-thought?topic=\(encodedTopic)&value=\(encodedValue)") else {
            throw NetworkError.invalidURL
        }
        
        print("Requesting thought from: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15 // Set a reasonable timeout
        request.httpMethod = "GET" // Assuming GET for generate-thought

        // Add Authorization header if token exists
        if let token = authManager.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            print("VoiceAPIManager: No auth token found for /generate-thought. Proceeding without.")
        }
        
        // MODIFIED: Declare data outside the do-catch to make it accessible in the catch block for ThoughtResponse decoding
        var responseData: Data?
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            responseData = data // Assign data here
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid HTTP response for /generate-thought")
                throw NetworkError.invalidResponse
            }
            
            print("VoiceAPIManager: /generate-thought response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                 print("VoiceAPIManager: Unauthorized (401) for /generate-thought.")
                 throw NetworkError.unauthorized
            }

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    let errorMessage = errorJson.error ?? errorJson.message ?? "Unknown server error"
                    print("VoiceAPIManager: Server error from /generate-thought: \(errorMessage)")
                    throw NetworkError.serverError(message: errorMessage)
                } else {
                     let responseBodyString = String(data: data, encoding: .utf8) ?? "No response body"
                     print("VoiceAPIManager: Server error (non-JSON) from /generate-thought: \(responseBodyString)")
                     throw NetworkError.serverError(message: "Server error: \(responseBodyString)")
                }
            }
            
            // Expecting JSON with a "thought" field
            do {
                let thoughtResponse = try JSONDecoder().decode(ThoughtResponse.self, from: data)
                print("VoiceAPIManager: Successfully received thought: \(thoughtResponse.thought)")
                return thoughtResponse.thought
            } catch {
                // Use responseData here, which is in scope
                let responseBodyForDecodingError = String(data: responseData ?? Data(), encoding: .utf8) ?? "No response body for decoding error"
                print("VoiceAPIManager: Failed to decode ThoughtResponse: \(error.localizedDescription). Body: \(responseBodyForDecodingError)")
                throw NetworkError.decodingError
            }

        } catch let error as NetworkError {
            print("VoiceAPIManager: NetworkError during thought generation: \(error.localizedDescription)")
            throw error
        } catch {
            print("VoiceAPIManager: Unexpected error during thought generation: \(error.localizedDescription)")
            throw NetworkError.unknown(message: error.localizedDescription)
        }
    }

    // New method for generating audio with cloned voice
    func generateAudioWithClonedVoice(topic: String, value: String) async throws -> Data {
        // Try primary URL first
        do {
            return try await generateAudioWithClonedVoiceWithURL(baseURL, topic: topic, value: value)
        } catch let error as NetworkError where error.isAuthError {
            print("VoiceAPIManager: Authentication error during audio generation: \(error.localizedDescription)")
            throw error // Re-throw auth errors directly
        }
        catch {
            print("Primary URL failed for audio generation: \(error.localizedDescription)")
            // Try fallbacks
            for fallbackURL in fallbackURLs {
                do {
                    return try await generateAudioWithClonedVoiceWithURL(fallbackURL, topic: topic, value: value)
                } catch let error as NetworkError where error.isAuthError {
                     print("VoiceAPIManager: Authentication error during audio generation on fallback: \(error.localizedDescription)")
                     throw error // Re-throw auth errors directly
                }
                catch {
                    print("Fallback URL \(fallbackURL) failed for audio generation: \(error.localizedDescription)")
                }
            }
            // If all URLs fail, throw the error
            throw error
        }
    }

    private func generateAudioWithClonedVoiceWithURL(_ urlString: String, topic: String, value: String) async throws -> Data {
        guard let url = URL(string: "\(urlString)/generate-audio-cloned") else {
            print("VoiceAPIManager: Invalid URL for /generate-audio-cloned: \(urlString)/generate-audio-cloned")
            throw NetworkError.invalidURL
        }
        
        print("Requesting cloned audio from: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // Increased timeout for audio generation

        // Add Authorization header if token exists
        if let token = authManager.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            print("VoiceAPIManager: Auth token is missing for /generate-audio-cloned. This endpoint requires authentication.")
            // Consider whether to throw an error or proceed if the endpoint allows unauthenticated access (it doesn't here)
            throw NetworkError.authenticationRequired
        }

        let requestBody: [String: Any] = [
            "topic": topic,
            "value": value, // This is the text to be converted to speech
            "stability": self.stability,
            "similarity_boost": self.similarityBoost
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            print("VoiceAPIManager: Failed to encode request body for /generate-audio-cloned: \(error.localizedDescription)")
            throw NetworkError.unknown(message: "Failed to create request: \(error.localizedDescription)")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("VoiceAPIManager: Invalid HTTP response for /generate-audio-cloned")
                throw NetworkError.invalidResponse
            }
            
            print("VoiceAPIManager: /generate-audio-cloned response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                 print("VoiceAPIManager: Unauthorized (401) for /generate-audio-cloned.")
                 throw NetworkError.unauthorized
            }

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    let errorMessage = errorJson.error ?? errorJson.message ?? "Unknown server error"
                    print("VoiceAPIManager: Server error from /generate-audio-cloned: \(errorMessage)")
                    throw NetworkError.serverError(message: errorMessage)
                } else {
                     let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                     print("VoiceAPIManager: Server error (non-JSON) from /generate-audio-cloned: \(responseBody)")
                     throw NetworkError.serverError(message: "Server error: \(responseBody)")
                }
            }
            
            // Check if the content type is audio
            if httpResponse.mimeType?.starts(with: "audio/") == true {
                print("VoiceAPIManager: Successfully received audio data from /generate-audio-cloned.")
                return data
            } else {
                let mimeTypeForLog = httpResponse.mimeType ?? "unknown"
                if let jsonError = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let message = jsonError["message"] as? String ?? jsonError["error"] as? String {
                    print("VoiceAPIManager: Expected audio, but received \(mimeTypeForLog) with JSON error: \(message)")
                    throw NetworkError.serverError(message: "Server returned non-audio content: \(message)")
                } else {
                    let responseBody = String(data: data, encoding: .utf8) ?? "No body content"
                    print("VoiceAPIManager: Expected audio, but received \(mimeTypeForLog): \(responseBody)")
                    throw NetworkError.serverError(message: "Expected audio data, but received type \(mimeTypeForLog). Body: \(responseBody)")
                }
            }

        } catch let error as NetworkError {
            print("VoiceAPIManager: NetworkError during cloned audio generation: \(error.localizedDescription)")
            throw error
        } catch {
            print("VoiceAPIManager: Unexpected error during cloned audio generation: \(error.localizedDescription)")
            throw NetworkError.unknown(message: error.localizedDescription)
        }
    }
    
    // MARK: - User Settings Management

    func loadSettingsFromAuth() {
        print("VoiceAPIManager: loadSettingsFromAuth() called")
        
        // First, populate UI from current user's settings if available
        DispatchQueue.main.async {
            if let userSettings = self.authManager.currentUser?.settings {
                print("VoiceAPIManager: Found current user settings - Language: \(userSettings.language), Stability: \(userSettings.stability), Similarity: \(userSettings.voiceSimilarity)")
                print("VoiceAPIManager: Current UI values BEFORE update - Language: \(self.language), Stability: \(self.stability), Similarity: \(self.similarityBoost)")
                
                self.language = userSettings.language
                self.stability = userSettings.stability
                self.similarityBoost = userSettings.voiceSimilarity
                self.addBackground = userSettings.addBackgroundSound
                self.backgroundVolume = userSettings.backgroundVolume
                
                print("VoiceAPIManager: Current UI values AFTER update - Language: \(self.language), Stability: \(self.stability), Similarity: \(self.similarityBoost)")
                print("VoiceAPIManager: Loaded settings from current user data")
            } else {
                print("VoiceAPIManager: No current user data available, fetching fresh data...")
                print("VoiceAPIManager: AuthManager current user: \(String(describing: self.authManager.currentUser))")
                
                // If no current user data, try to fetch it
                Task {
                    await self.authManager.fetchAndUpdateCurrentUser()
                    // After fetching, load the settings again
                    DispatchQueue.main.async {
                        if let userSettings = self.authManager.currentUser?.settings {
                            print("VoiceAPIManager: Found settings after fresh fetch - Language: \(userSettings.language), Stability: \(userSettings.stability), Similarity: \(userSettings.voiceSimilarity)")
                            
                            self.language = userSettings.language
                            self.stability = userSettings.stability
                            self.similarityBoost = userSettings.voiceSimilarity
                            self.addBackground = userSettings.addBackgroundSound
                            self.backgroundVolume = userSettings.backgroundVolume
                            print("VoiceAPIManager: Loaded settings after fresh fetch")
                        } else {
                            print("VoiceAPIManager: Still no current user data after fetch!")
                        }
                    }
                }
            }
        }
    }

    func updateUserSettings() async {
        guard let token = authManager.authToken else {
            await MainActor.run {
                self.errorMessage = "Authentication token not found. Please log in."
            }
            return
        }

        guard let url = URL(string: "\(baseURL)/update-settings") else {
            await MainActor.run {
                self.errorMessage = "Invalid URL for updating settings."
            }
            return
        }

        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Assuming UserSettingsPayload is defined and matches backend expectations
        // Also assuming Language enum has a String rawValue
        let payload = UserSettingsPayload(
            language: self.language.rawValue,
            voiceSimilarity: self.similarityBoost, // Corrected label and order
            stability: self.stability,             // Corrected order
            addBackgroundSound: self.addBackground, // Corrected label
            backgroundVolume: self.backgroundVolume  // Corrected label
        )

        do {
            let jsonData = try JSONEncoder().encode(payload)
            request.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    self.errorMessage = "Invalid response from server."
                }
                return
            }

            if httpResponse.statusCode == 200 {
                print("VoiceAPIManager: User settings updated successfully.")
                // Optionally, update AuthManager's currentUser.settings here or re-fetch
                // For now, we assume the local VoiceAPIManager state is the source of truth after update.
                // To reflect changes in AuthManager immediately:
                let updatedSettings = UserSettings(
                    language: self.language,
                    voiceSimilarity: self.similarityBoost, // Corrected order
                    stability: self.stability,             // Corrected order
                    addBackgroundSound: self.addBackground,
                    backgroundVolume: self.backgroundVolume,
                    voiceIds: self.authManager.currentUser?.settings.voiceIds // Preserve existing voice IDs
                )
                self.authManager.updateCurrentUserSettings(updatedSettings) // Uncommented and should now work


            } else if httpResponse.statusCode == 401 {
                await MainActor.run {
                    self.errorMessage = "Unauthorized. Please log in again."
                    // Consider calling authManager.logout() or similar
                }
            } else {
                var errorMsg = "Failed to update settings. Status: \(httpResponse.statusCode)"
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    errorMsg = errorResponse.message ?? errorResponse.error ?? errorMsg
                }
                await MainActor.run {
                    self.errorMessage = errorMsg
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error updating settings: \(error.localizedDescription)"
            }
        }
        await MainActor.run {
            self.isLoading = false
        }
    }
}

// Add ErrorResponse struct for decoding server error messages if they are JSON
struct ErrorResponse: Decodable {
    let error: String?
    let message: String? // Some Flask responses might use 'message'
}

// ADDED: Define TokenResponse
struct TokenResponse: Decodable {
    let token: String
}

// ADDED: Define ThoughtResponse
struct ThoughtResponse: Decodable {
    let thought: String
}

// ADDED: User struct for decoding /me endpoint response
struct User: Codable, Identifiable {
    let id: String // Changed from Int to String to match backend
    let username: String
    let email: String
    var settings: UserSettings
    let voiceCloneId: String? // Added to match backend response
    let voiceIds: [String]? // Added to match backend response

    enum CodingKeys: String, CodingKey {
        case id = "user_id" // Map user_id from backend to id in Swift
        case username
        case email
        case settings
        case voiceCloneId = "voice_clone_id" // Map voice_clone_id from backend
        case voiceIds = "voice_ids" // Map voice_ids from backend
    }
}


enum NetworkError: Error, LocalizedError {
    case invalidURL
    case connectionFailed
    case invalidResponse
    case decodingError
    case serverError(message: String)
    case authenticationRequired // Added
    case unauthorized // Added for 401 specifically
    case unknown(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The URL provided was invalid."
        case .connectionFailed: return "Failed to connect to the server. Please check your network connection and the server address."
        case .invalidResponse: return "The server returned an invalid response."
        case .decodingError: return "Failed to decode the server's response."
        case .serverError(let message): return "Server error: \(message)" // Corrected interpolation
        case .authenticationRequired: return "Authentication is required for this action. Please log in."
        case .unauthorized: return "Unauthorized. Your session may have expired or your credentials are not valid. Please log in again."
        case .unknown(let message): return "An unknown error occurred: \(message)" // Corrected interpolation
        }
    }

    // Helper to check if the error is an authentication/authorization error
    var isAuthError: Bool {
        switch self {
        case .authenticationRequired, .unauthorized:
            return true
        default:
            return false
        }
    }
}


enum RecordingError: Error, LocalizedError {
    case permissionDenied
    case recordingFailed
    case playbackFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .recordingFailed:
            return "Error recording audio"
        case .playbackFailed:
            return "Error playing audio"
        }
    }
}

// MARK: - Audio Manager
class AudioManager: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var hasRecording = false
    @Published var isPlaying = false
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var recordingURL: URL?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func startRecording() async throws {
        guard await requestMicrophonePermission() else {
            throw RecordingError.permissionDenied
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("recording.m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            
            isRecording = true
            recordingTime = 0
            
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                self.recordingTime += 0.1
            }
        } catch {
            throw RecordingError.recordingFailed
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        hasRecording = true
    }
    
    func playRecording() throws {
        guard let url = recordingURL else { return }
        
        do {
            // Add this before playing
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        } catch {
            print("AudioManager: Failed to override output port to speaker: \(error.localizedDescription)") // Corrected interpolation
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            throw RecordingError.playbackFailed
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
    }
    
    func getRecordingData() -> Data? {
        guard let url = recordingURL else { return nil }
        return try? Data(contentsOf: url)
    }
    
    func playData(_ data: Data) throws {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Error reproduciendo datos de audio: \(error)")
            throw RecordingError.playbackFailed
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

// MARK: - Edit Screen View
struct EditScreenView: View {
    @ObservedObject var apiManager: VoiceAPIManager
    let onBackTapped: () -> Void
    
    @State private var showVoiceCloneSheet = false
    @State private var showSaveConfirmation = false
    @State private var saveStatusMessage = ""

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
                            // Settings Icon with glow effect
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
                                
                                Image(systemName: "gearshape.fill")
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
                                Text("Settings")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                Text("Customize your AI voice experience")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 20)
                        
                        // Language Preference Section
                        SettingsSection(
                            title: "Language Preference",
                            icon: "globe.americas.fill",
                            iconColor: Color(.systemGreen)
                        ) {
                            LanguageSelectionCard(apiManager: apiManager)
                        }
                        
                        // Voice Settings Section
                        SettingsSection(
                            title: "Voice Quality",
                            icon: "waveform",
                            iconColor: Color(.systemBlue)
                        ) {
                            VStack(spacing: 20) {
                                SliderCard(
                                    title: "Voice Stability",
                                    subtitle: "Controls consistency and predictability",
                                    value: $apiManager.stability,
                                    range: 0.0...1.0,
                                    step: 0.05,
                                    icon: "dial.high.fill"
                                )
                                
                                SliderCard(
                                    title: "Voice Similarity", 
                                    subtitle: "How closely it matches your voice",
                                    value: $apiManager.similarityBoost,
                                    range: 0.0...1.0,
                                    step: 0.05,
                                    icon: "person.crop.circle.fill"
                                )
                            }
                        }
                        
                        // Audio Enhancement Section
                        SettingsSection(
                            title: "Audio Enhancement",
                            icon: "speaker.wave.3.fill",
                            iconColor: Color(.systemOrange)
                        ) {
                            VStack(spacing: 20) {
                                ToggleCard(
                                    title: "Background Sound",
                                    subtitle: "Add ambient audio to your recordings",
                                    isOn: $apiManager.addBackground,
                                    icon: "music.note"
                                )
                                
                                if apiManager.addBackground {
                                    SliderCard(
                                        title: "Background Volume",
                                        subtitle: "Adjust ambient audio level",
                                        value: $apiManager.backgroundVolume,
                                        range: 0.0...1.0,
                                        step: 0.05,
                                        icon: "speaker.wave.2.fill"
                                    )
                                    .transition(.opacity.combined(with: .slide))
                                }
                            }
                            .animation(.easeInOut(duration: 0.3), value: apiManager.addBackground)
                        }
                        
                        // Voice Clone Section
                        SettingsSection(
                            title: "Voice Cloning",
                            icon: "person.wave.2.fill",
                            iconColor: Color(.systemPurple)
                        ) {
                            VoiceCloneCard(showVoiceCloneSheet: $showVoiceCloneSheet)
                        }
                        
                        // Save Settings Button
                        Button(action: {
                            Task {
                                await apiManager.updateUserSettings()
                                saveStatusMessage = "Settings saved successfully!"
                                showSaveConfirmation = true
                            }
                        }) {
                            HStack(spacing: 12) {
                                if apiManager.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .medium))
                                }
                                
                                Text(apiManager.isLoading ? "Saving..." : "Save Settings")
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
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color(.systemBlue).opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(apiManager.isLoading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") {
                    onBackTapped()
                }
                .font(.system(size: 17, weight: .medium))
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    onBackTapped()
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(.systemBlue),
                            Color(.systemPurple)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
        }
        .onAppear {
            // Always fetch fresh user data when settings screen appears
            Task {
                await apiManager.authManager.fetchAndUpdateCurrentUser()
                apiManager.loadSettingsFromAuth()
            }
            apiManager.errorMessage = nil
        }
        .onReceive(apiManager.authManager.$currentUser) { user in
            // React to changes in current user data
            if user != nil {
                apiManager.loadSettingsFromAuth()
            }
        }
        .sheet(isPresented: $showVoiceCloneSheet) {
            VoiceCloneSheet(apiManager: apiManager)
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { apiManager.errorMessage != nil },
            set: { _ in apiManager.errorMessage = nil }
        )) {
            Button("OK") { apiManager.errorMessage = nil }
        } message: {
            Text(apiManager.errorMessage ?? "An error occurred")
        }
        .alert("Settings Saved", isPresented: $showSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text(saveStatusMessage)
        }
    }
}

// MARK: - Settings Support Views

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 24)
            
            content
        }
    }
}

struct LanguageSelectionCard: View {
    @ObservedObject var apiManager: VoiceAPIManager
    
    var body: some View {
        Menu {
            ForEach(Language.allCases) { lang in
                Button(action: {
                    apiManager.language = lang
                }) {
                    HStack {
                        Text(lang.displayName)
                        if apiManager.language == lang {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(.systemGreen))
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Language")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(apiManager.language.displayName)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
}

struct SliderCard: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let icon: String
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(.systemBlue))
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(value * 100))%")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 50, alignment: .trailing)
            }
            
            HStack(spacing: 12) {
                Text("\(Int(range.lowerBound * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Slider(value: $value, in: range, step: step)
                    .accentColor(Color(.systemBlue))
                
                Text("\(Int(range.upperBound * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct ToggleCard: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Color(.systemOrange))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .scaleEffect(0.9)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct VoiceCloneCard: View {
    @Binding var showVoiceCloneSheet: Bool
    
    var body: some View {
        Button(action: {
            showVoiceCloneSheet = true
        }) {
            HStack(spacing: 16) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(.systemPurple))
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Voice Clone")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Record, test, or replace your AI voice")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Audio Player View
struct AudioPlayerView: View {
    let audioData: Data
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if duration > 0 {
                        ProgressView(value: currentTime, total: duration)
                            .tint(.blue)
                        
                        HStack {
                            Text(formatTime(currentTime))
                            Spacer()
                            Text(formatTime(duration))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        Text("Generated audio")
                            .font(.subheadline)
                    }
                }
            }
        }
        .onAppear {
            setupAudioPlayer()
        }
        .onDisappear {
            stopTimer()
            audioPlayer?.stop()
        }
    }
    
    private func setupAudioPlayer() {
        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
        } catch {
            print("Error setting up audio player: \(error)")
        }
    }
    
    private func togglePlayback() {
        guard let player = audioPlayer else { return }
        
        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
            } catch {
                print("AudioPlayerView: Failed to override output port to speaker: \(error.localizedDescription)")
            }
            player.play()
            startTimer()
        }
        isPlaying.toggle()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = audioPlayer else { return }
            currentTime = player.currentTime
            
            if !player.isPlaying {
                isPlaying = false
                stopTimer()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Peek Visualization View
struct PeekVisualizationView: View {
    let selectedButton: String
    let inputText: String
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Selected Button Display
                VStack(spacing: 12) {
                    Text("Selected Button")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text(selectedButton.isEmpty ? "No button selected" : selectedButton)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(12)
                }
                
                // Input Text Display
                VStack(spacing: 12) {
                    Text("Input Text")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                    
                    ScrollView {
                        Text(inputText.isEmpty ? "No text entered" : inputText)
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: 60)
                    .background(Color.gray.opacity(0.8))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)
        }
    }
}

struct RecordingRow: View {
    let recording: RecordingData
    let isSelected: Bool
    let isPlaying: Bool
    let currentTime: Double
    let totalTime: Double
    let onTap: (RecordingData) -> Void
    let onPlay: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Main recording row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recording.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(recording.date)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if !isSelected {
                    Text(recording.duration)
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                } else {
                    // Three dots menu
                    Button(action: {}) {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap(recording)
            }
            
            // Expanded playback controls
            if isSelected {
                VStack(spacing: 16) {
                    // Progress bar
                    VStack(spacing: 8) {
                        HStack {
                            // Progress track
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 2)
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: max(0, geometry.size.width * (currentTime / totalTime)), height: 2)
                                    
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 8, height: 8)
                                        .offset(x: max(0, geometry.size.width * (currentTime / totalTime) - 4))
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(.horizontal, 20)
                        
                        // Time labels
                        HStack {
                            Text(formatTime(currentTime))
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("-\(formatTime(totalTime - currentTime))")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Control buttons
                    HStack(spacing: 40) {
                        // Waveform button
                        Button(action: {}) {
                            Image(systemName: "waveform")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        }
                        
                        // Rewind 15s
                        Button(action: {}) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 44, height: 44)
                                
                                Text("15")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Image(systemName: "gobackward")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .offset(y: -8)
                            }
                        }
                        
                        // Play/Pause
                        Button(action: onPlay) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        
                        // Forward 15s
                        Button(action: {}) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 44, height: 44)
                                
                                Text("15")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Image(systemName: "goforward")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .offset(y: -8)
                            }
                        }
                        
                        // Delete button
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .background(Color.black)
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
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
                                Text("Join Voice Memos AI")
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
                // Premium gradient background
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

// MARK: - Custom Auth Text Field Component

struct AuthTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.white)
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
}


// MARK: - AuthManager (With Network Logic and Keychain)
import Security // For Keychain

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var authToken: String? = nil
    @Published var isLoading: Bool = false // For UI updates during network calls
    @Published var showError: Bool = false // ADDED: For displaying errors in the UI
    @Published var errorMessage: String? = nil // ADDED: Stores the error message
    @Published var currentUser: User? = nil // ADDED: To store current user data including settings

    private let baseURL = "https://voicememos-production.up.railway.app" // MODIFIED: Use Railway production URL
    // --- TEMPORARY DIAGNOSTIC for connection issues ---
    // private let baseURL = "http://127.0.0.1:5002" // Old localhost, incorrect for simulator/device
    // --- END TEMPORARY DIAGNOSTIC ---

    private let keychainService = "com.yourapp.VoiceMemosAI" // Unique identifier for keychain service
    private let keychainAccount = "userToken" // Key for the token

    init() {
        loadTokenFromKeychain() // Load token on init
    }

    func createAccount(username: String, email: String, password: String, activationCode: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/register") else { // FIX: Corrected URL interpolation
            print("Invalid URL for registration")
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL for registration."
                self.showError = true
            }
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "username": username,
            "email": email,
            "password": password,
            "activation_code": activationCode
        ]

        do {
            request.httpBody = try JSONEncoder().encode(body)
       
        } catch {
            self.errorMessage = "Failed to encode request: \(error.localizedDescription)" // FIX: Use errorMessage
            isLoading = false
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                self.errorMessage = "Invalid response from server." // FIX: Use errorMessage
                isLoading = false
                return false
            }

            let bodyStringForLogging = String(data: data, encoding: .utf8) ?? "empty_body_for_logging"
            print("Create Account Response: Status \(httpResponse.statusCode), Body: \(bodyStringForLogging)")


            if httpResponse.statusCode == 201 { // Successfully created
                isLoading = false
                return true
            } else {
                // Try to parse error message from backend
                let responseBody = String(data: data, encoding: .utf8) // Initialize here for error reporting
                if let errorJson = try? JSONDecoder().decode([String: String].self, from: data),
                   let errMsg = errorJson["error"] ?? errorJson["message"] { // Check for "message" too
                    self.errorMessage = errMsg // FIX: Use errorMessage
                } else {
                    self.errorMessage = "Failed to create account. Status: \(httpResponse.statusCode). Details: \(responseBody ?? "No details provided")" // FIX: Use errorMessage
                }
                isLoading = false
                return false
            }
        } catch {
            print("Detailed network error in createAccount: \(error)")
            self.errorMessage = "Network request failed: \(error.localizedDescription). Details: \(error)" // FIX: Use errorMessage
            isLoading = false
            return false
        }
    }

    func login(emailOrUsername: String, password: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/login") else { // FIX: Corrected URL interpolation
            print("Invalid URL for login")
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL for login."
                self.showError = true
            }
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": emailOrUsername, // Backend expects 'email' for email/username
            "password": password
        ]

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            print("Detailed encoding error in login: \(error)")
            self.errorMessage = "Failed to encode request: \(error.localizedDescription). Details: \(error)" // FIX: Use errorMessage
            isLoading = false
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                self.errorMessage = "Invalid response from server." // FIX: Use errorMessage
                isLoading = false
                return false
            }
            
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("Login Response Status: \(httpResponse.statusCode)")
            print("Login Response Body: \(responseBody)")

            if httpResponse.statusCode == 200 {
                do {
                    let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                    await MainActor.run {
                        self.authToken = tokenResponse.token
                        self.isAuthenticated = true
                        self.saveTokenToKeychain(token: tokenResponse.token) // Save token persistently
                        self.errorMessage = nil // Clear error on success
                        self.showError = false
                    }
                    // After successful login, fetch user details which include settings
                    await fetchAndUpdateCurrentUser() 
                    return true
                } catch {
                    print("Detailed decoding error in login: \(error)")
                    self.errorMessage = "Failed to decode token: \(error.localizedDescription). Details: \(error)" // FIX: Use errorMessage
                    isLoading = false
                    return false
                }
            } else {
                 if let json = try? JSONDecoder().decode([String: String].self, from: data),
                    let message = json["error"] ?? json["message"] { // Prefer "error" then "message"
                    self.errorMessage = message // FIX: Use errorMessage
                 } else {
                    let responseBodyString = String(data: data, encoding: .utf8) ?? "No details provided"
                    self.errorMessage = "Login failed. Status: \(httpResponse.statusCode). Details: \(responseBodyString)" // FIX: Use errorMessage
                }
                isLoading = false
                return false
            }
        } catch {
            print("Detailed network error in login: \(error)")
            self.errorMessage = "Network request failed: \(error.localizedDescription). Details: \(error)" // FIX: Use errorMessage
            isLoading = false
            return false
        }
    }
    
    func logout() {
        self.authToken = nil
        self.isAuthenticated = false
        deleteTokenFromKeychain() // Remove persisted token
        DispatchQueue.main.async {
            self.currentUser = nil // Clear current user data on logout
        }
    }

    // MARK: - User Data Management (New)
    // MODIFIED: Made public so VoiceAPIManager can call it
    func fetchAndUpdateCurrentUser() async {
        guard let token = self.authToken else {
            print("AuthManager: No auth token available to fetch user data.")
            return
        }
        guard let url = URL(string: "\(baseURL)/me") else {
            print("AuthManager: Invalid URL for /me endpoint.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("AuthManager: Invalid response when fetching user data.")
                return
            }
            
            print("AuthManager: /me endpoint response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                // Add debugging to see the raw response
                if let responseString = String(data: data, encoding: .utf8) {
                    print("AuthManager: /me endpoint raw response: \(responseString)")
                }
                
                do {
                    let fetchedUser = try JSONDecoder().decode(User.self, from: data)
                    DispatchQueue.main.async {
                        self.currentUser = fetchedUser
                        print("AuthManager: Successfully fetched and updated current user: \(fetchedUser.username)")
                        print("AuthManager: User settings - Language: \(fetchedUser.settings.language), Stability: \(fetchedUser.settings.stability), Similarity: \(fetchedUser.settings.voiceSimilarity)")
                    }
                } catch {
                    print("AuthManager: Failed to decode User from /me response: \(error)")
                    if let decodingError = error as? DecodingError {
                        print("AuthManager: Decoding error details: \(decodingError)")
                    }
                }
            } else if httpResponse.statusCode == 401 {
                // Only log out if the token is actually invalid (401)
                print("AuthManager: Token is invalid (401). Logging out.")
                DispatchQueue.main.async {
                    self.logout()
                }
            } else {
                // For other errors, just log but don't logout
                print("AuthManager: Failed to fetch user data. Status: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("AuthManager: Error response body: \(responseString)")
                }
            }
        } catch {
            // Don't logout on network errors, just log them
            print("AuthManager: Error fetching or decoding user data: \(error.localizedDescription)")
        }
    }

    func updateCurrentUserSettings(_ settings: UserSettings) {
        DispatchQueue.main.async {
            if self.currentUser != nil {
                self.currentUser!.settings = settings
                print("AuthManager: Local currentUser settings updated.")
                // Note: This only updates the local copy. The settings are saved to the backend
                // by VoiceAPIManager.updateUserSettings(), which should be the source of truth for saving.
            } else {
                print("AuthManager: Attempted to update settings for a nil currentUser.")
            }
        }
    }


    // MARK: - Keychain Management
    func saveTokenToKeychain(token: String) {
        guard let data = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary) // Delete any existing item first
       
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error saving token to keychain: \(status)")
        } else {
            print("Token saved to keychain successfully.")
        }
    }

    func loadTokenFromKeychain() {
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
               let token = String(data: retrievedData, encoding: .utf8) {
                self.authToken = token
                self.isAuthenticated = true // Set authenticated state when token is loaded
                print("Token loaded from keychain.")
                // Fetch user data to ensure the token is still valid
                Task {
                    await fetchAndUpdateCurrentUser()
                }
            } else {
                 print("Failed to decode token from keychain.")
            }
        } else if status == errSecItemNotFound {
            print("No token found in keychain.")
        } 
        else {
            print("Error loading token from keychain: \(status)")
        }
    }

    func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Error deleting token from keychain: \(status)")
        } else {
             print("Token deleted from keychain or was not found.")
        }
    }
}

// MARK: - Voice Clone Sheet
struct VoiceCloneSheet: View {
    @Environment(\.presentationMode) var presentationMode

    @ObservedObject var apiManager: VoiceAPIManager

    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var avDelegate: AVDelegate?
    @State private var statusMessage: String?
    @State private var existingCloneId: String?
    @State private var isUploading = false
    @State private var showOverwriteAlert = false
    @State private var recordingTime: Double = 0
    @State private var recordingTimer: Timer?
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.3, count: 50)
    @State private var animationTimer: Timer?

    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.blue)
                    .font(.system(size: 17, weight: .medium))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
                
                if let cloneId = existingCloneId {
                    // Existing clone view
                    VStack(spacing: 40) {
                        VStack(spacing: 20) {
                            // Success icon and status
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.2))
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.green)
                            }
                            
                            VStack(spacing: 8) {
                                Text("Voice Clone Active")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Your voice clone is ready and being used for audio generation.")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                            }
                        }
                        
                        // Voice Clone Info Section
                        // VStack(spacing: 16) {
                        //     HStack {
                        //         VStack(alignment: .leading, spacing: 4) {
                        //             Text("Clone ID")
                        //                 .font(.system(size: 12, weight: .medium))
                        //                 .foregroundColor(.gray)
                        //             Text(cloneId)
                        //                 .font(.system(size: 14, weight: .medium))
                        //                 .foregroundColor(.white)
                        //                 .lineLimit(1)
                        //                 .truncationMode(.middle)
                        //         }
                                
                        //         Spacer()
                                
                        //         Button(action: {
                        //             UIPasteboard.general.string = cloneId
                        //             // Provide haptic feedback
                        //             let generator = UIImpactFeedbackGenerator(style: .light)
                        //             generator.impactOccurred()
                                    
                        //             // Temporary status message
                        //             statusMessage = "Clone ID copied to clipboard"
                        //             DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        //                 if statusMessage == "Clone ID copied to clipboard" {
                        //                     statusMessage = nil
                        //                 }
                        //             }
                        //         }) {
                        //             Image(systemName: "doc.on.doc")
                        //                 .font(.system(size: 16))
                        //                 .foregroundColor(.blue)
                        //                 .padding(8)
                        //                 .background(Color.blue.opacity(0.15))
                        //                 .cornerRadius(8)
                        //         }
                        //     }
                        //     .padding(.horizontal, 20)
                        //     .padding(.vertical, 12)
                        //     .background(Color.gray.opacity(0.1))
                        //     .cornerRadius(12)
                        // }
                        // .padding(.horizontal, 20)
                        
                        // Management Options
                        VStack(spacing: 12) {
                            // Test Voice Clone Button
                            Button("Test Voice Clone") {
                                // This could trigger a test generation or play a sample
                                statusMessage = "Testing feature coming soon..."
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    if statusMessage == "Testing feature coming soon..." {
                                        statusMessage = nil
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue.opacity(0.8))
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                            .cornerRadius(10)
                            
                            // Replace Voice Clone Button
                            Button("Replace Voice Clone") {
                                showOverwriteAlert = true
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange.opacity(0.8))
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal, 20)
                    }
                    .alert("Replace Voice Clone?", isPresented: $showOverwriteAlert) {
                        Button("Replace", role: .destructive) {
                            Task { await deleteClone() }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Are you sure you want to replace your existing voice clone? This will delete your current clone and allow you to record a new one.")
                    }
                } else {
                    // Recording interface
                    VStack(spacing: 40) {
                        // Title section
                        VStack(spacing: 12) {
                            Text("Create Voice Clone")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text(isRecording ? "Recording your voice..." : "Tap to record")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                        }
                        
                        // Recording time and waveform
                        if isRecording || recordingURL != nil {
                            VStack(spacing: 20) {
                                // Recording time
                                Text(formatRecordingTime(recordingTime))
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.white)
                                    .monospacedDigit()
                                
                                // Simple waveform visualization
                                if isRecording {
                                    HStack(spacing: 3) {
                                        ForEach(0..<20, id: \.self) { index in
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.blue)
                                                .frame(width: 4, height: audioLevels[index] * 40 + 10)
                                                .animation(.easeInOut(duration: 0.1), value: audioLevels[index])
                                        }
                                    }
                                    .frame(height: 60)
                                }
                            }
                        }
                        
                        // Large circular recording button
                        ZStack {
                            // Outer pulsing ring (only when recording)
                            if isRecording {
                                Circle()
                                    .stroke(Color.red.opacity(0.3), lineWidth: 4)
                                    .frame(width: 200, height: 200)
                                    .scaleEffect(isRecording ? 1.2 : 1.0)
                                    .opacity(isRecording ? 0.0 : 1.0)
                                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isRecording)
                            }
                            
                            // Main button circle
                            Circle()
                                .fill(isRecording ? Color.red : Color.blue)
                                .frame(width: 150, height: 150)
                                .overlay(
                                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 60, weight: .medium))
                                        .foregroundColor(.white)
                                )
                                .scaleEffect(isRecording ? 0.9 : 1.0)
                                .animation(.easeInOut(duration: 0.1), value: isRecording)
                        }
                        .onTapGesture {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        }
                        
                        // Play button (when recording exists)
                        if recordingURL != nil && !isRecording {
                            Button(action: {
                                if isPlaying {
                                    audioPlayer?.stop()
                                    isPlaying = false
                                } else {
                                    playRecording()
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                        .font(.system(size: 20))
                                    Text(isPlaying ? "Stop Playback" : "Play Recording")
                                        .font(.system(size: 17, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(25)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Bottom section
                VStack(spacing: 20) {
                    if let msg = statusMessage {
                        Text(msg)
                            .font(.system(size: 16))
                            .foregroundColor(msg.contains("success") || msg.contains("created") ? .green : .orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // Generate button (only show when we have a recording and no existing clone)
                    if recordingURL != nil && existingCloneId == nil && !isRecording {
                        Button(action: generateClone) {
                            HStack(spacing: 12) {
                                if isUploading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "waveform.badge.plus")
                                        .font(.system(size: 20))
                                }
                                
                                Text(isUploading ? "Creating Voice Clone..." : "Generate Voice Clone")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .disabled(isUploading)
                            .opacity(isUploading ? 0.7 : 1.0)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            Task { await fetchExistingClone() }
        }
        .onDisappear {
            stopAllTimers()
        }
    }

    private func fetchExistingClone() async {
        print("DEBUG: Starting fetchExistingClone()")
        guard let token = apiManager.authManager.authToken,
              let url = URL(string: "\(apiManager.baseURL)/me") else { 
            print("DEBUG: Failed to get token or URL")
            return 
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            print("DEBUG: Making request to /me endpoint")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("DEBUG: Response status code: \(httpResponse.statusCode)")
            }
            
            // First, let's see what the raw response looks like
            if let responseString = String(data: data, encoding: .utf8) {
                print("DEBUG: Raw response: \(responseString)")
            }
            
            // Define a struct to properly decode the /me endpoint response
            struct MeResponse: Codable {
                let user_id: String
                let username: String
                let email: String
                let voice_clone_id: String?
                let voice_ids: [String]?
                let settings: [String: AnyCodable]?
            }
            
            let decoder = JSONDecoder()
            let meResponse = try decoder.decode(MeResponse.self, from: data)
            
            print("DEBUG: Successfully decoded response")
            print("DEBUG: voice_clone_id = \(meResponse.voice_clone_id ?? "nil")")
            
            // Update existingCloneId on main thread
            await MainActor.run {
                if let cloneId = meResponse.voice_clone_id, !cloneId.isEmpty {
                    print("DEBUG: Setting existingCloneId to: \(cloneId)")
                    existingCloneId = cloneId
                } else {
                    print("DEBUG: No voice_clone_id found or it's empty")
                    existingCloneId = nil
                }
            }
            
        } catch {
            print("DEBUG: Error in fetchExistingClone: \(error)")
            await MainActor.run {
                statusMessage = "Failed to load existing clone: \(error.localizedDescription)"
            }
        }
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.statusMessage = "Microphone permission denied"
                    return
                }
                
                do {
                    try session.setCategory(.playAndRecord, mode: .default)
                    try session.setActive(true)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("voiceclone.m4a")
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1
                    ]
                    self.audioRecorder = try AVAudioRecorder(url: url, settings: settings)
                    self.audioRecorder?.isMeteringEnabled = true
                    self.audioRecorder?.record()
                    self.isRecording = true
                    self.recordingURL = url
                    self.recordingTime = 0
                    self.statusMessage = nil
                    
                    // Start recording timer
                    self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        self.recordingTime += 0.1
                        self.audioRecorder?.updateMeters()
                    }
                    
                    // Start animation timer for waveform
                    self.startWaveformAnimation()
                    
                } catch {
                    self.statusMessage = "Recording failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        stopAllTimers()
    }

    private func startWaveformAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Simulate audio levels for visual effect
            for i in 0..<audioLevels.count {
                audioLevels[i] = CGFloat.random(in: 0.2...1.0)
            }
        }
    }

    private func stopAllTimers() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func formatRecordingTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func playRecording() {
        guard let url = recordingURL else {
            statusMessage = "No recording available to play."
            return
        }

        // Stop existing player if any and reset state
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
        }
        self.isPlaying = false
        self.audioPlayer?.delegate = nil // Clear old delegate
        self.audioPlayer = nil
        self.avDelegate = nil

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            self.audioPlayer = newPlayer

            let newDelegate = AVDelegate {
                DispatchQueue.main.async {
                    isPlaying = false
                }
            }
            self.avDelegate = newDelegate
            newPlayer.delegate = newDelegate

            if newPlayer.prepareToPlay() {
                newPlayer.play()
                self.isPlaying = true
                self.statusMessage = nil // Clear status on successful play
            } else {
                self.statusMessage = "Failed to prepare audio for playback."
                self.isPlaying = false
            }
        } catch {
            self.statusMessage = "Playback failed: \(error.localizedDescription)"
            self.isPlaying = false
            // Ensure cleanup on error
            self.audioPlayer = nil
            self.avDelegate = nil
        }
    }

    private func generateClone() {
        guard let url = recordingURL,
              let token = apiManager.authManager.authToken else { return }
        isUploading = true
        statusMessage = "Processing your voice recording..."
        Task {
            do {
                let endpoint = "\(apiManager.baseURL)/generate-voice-clone"
                var request = URLRequest(url: URL(string: endpoint)!)
                request.httpMethod = "POST"
                let boundary = UUID().uuidString
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                var body = Data()
                // Append file field
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"voiceclone.m4a\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
                body.append(try Data(contentsOf: url))
                body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                request.httpBody = body

                let (data, response) = try await URLSession.shared.data(for: request)
                await MainActor.run {
                    if let json = try? JSONDecoder().decode([String: String].self, from: data),
                       let cloneId = json["voice_clone_id"] {
                        self.existingCloneId = cloneId
                        self.statusMessage = "Voice clone created successfully!"
                        self.recordingURL = nil // Clear the recording
                        self.recordingTime = 0
                    } else {
                        self.statusMessage = "Failed to create voice clone. Please try again."
                    }
                    self.isUploading = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Upload failed: \(error.localizedDescription)"
                    self.isUploading = false
                }
            }
        }
    }

    // MARK: - Delete existing clone
    private func deleteClone() async {
        guard let token = apiManager.authManager.authToken,
              let url = URL(string: "\(apiManager.baseURL)/delete-voice-clone") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            await MainActor.run {
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    self.existingCloneId = nil
                    self.statusMessage = "Voice clone deleted. You can now record a new one."
                } else {
                    let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                    self.statusMessage = "Delete failed: \(msg)"
                }
            }
        } catch {
            await MainActor.run {
                self.statusMessage = "Delete error: \(error.localizedDescription)"
            }
        }
    }
}

// AVAudioPlayerDelegate helper
class AVDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinishPlaying: (() -> Void)? // Replaced @Binding var isPlaying

    init(onFinishPlaying: (() -> Void)?) { // Initializer now takes a closure
        self.onFinishPlaying = onFinishPlaying
        super.init() // Added call to super.init()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinishPlaying?() // Call the closure instead of setting isPlaying directly
    }
}

