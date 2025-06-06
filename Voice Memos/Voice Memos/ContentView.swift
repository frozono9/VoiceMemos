import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedButton: String = ""
    @State private var inputText: String = ""
    @State private var currentScreen: AppScreen = .buttonSelection
    @State private var generatedRecording: RecordingData? = nil
    @StateObject private var apiManager = VoiceAPIManager() // Added
    @State private var generationError: String? = nil // Added for error display

    enum AppScreen {
        case buttonSelection
        case textInput
        case voiceMemos
        case editScreen
    }
    
    var body: some View {
        ZStack { // Added ZStack for potential global loading/error overlay
            switch currentScreen {
            case .buttonSelection:
                ButtonSelectionView(selectedButton: $selectedButton) {
                    currentScreen = .textInput
                }
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
                        currentScreen = .editScreen
                    }
                )
            case .editScreen:
                EditScreenView(
                    selectedButton: selectedButton,
                    inputText: inputText,
                    apiManager: apiManager, // Pass apiManager
                    onBackTapped: { newRecording in
                        if let newRecording = newRecording {
                            generatedRecording = newRecording
                        }
                        currentScreen = .voiceMemos
                    }
                )
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
            // Given the context of voice memos, 16kHz mono is plausible.
            // If the backend standardizes on, say, 24000 Hz, 16-bit, mono for ElevenLabs, then it's 48000 bytes/sec.
            // Let's stick to a more common voice memo rate or make it configurable if possible.
            // For a rough estimate, if it's raw PCM data.
            // A common rate for voice is 16kHz, 16-bit mono. Bytes per second = 16000 * 2 = 32000.
            // If the backend output is MP3 or another compressed format, this calculation is incorrect.
            // However, the AVAudioPlayer path is preferred. This is just a fallback.
            // Let's assume the 16000 was for a specific 8-bit scenario or a rough estimate.
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
        
        // Create and set a placeholder recording immediately
        let placeholderRecording = RecordingData(
            id: pendingRecordingID,
            title: placeholderTitle,
            date: formattedDate(Date()),
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
                    date: formattedDate(Date()),
                    duration: estimateDuration(from: audioData),
                    audioData: audioData
                )
                
                await MainActor.run {
                    self.generatedRecording = finalRecording // Update the recording
                    // isLoadingAudio = false // Removed
                    print("ContentView: Audio generation successful, recording updated.")
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
                        date: formattedDate(Date()),
                        duration: "Error"
                    )
                    self.generatedRecording = errorRecording
                }
            }
        }
    }
}

struct ButtonSelectionView: View {
    @Binding var selectedButton: String
    let onButtonSelected: () -> Void
    
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
            RecordingData(title: "Carrer dels Ametllers, 9 24", date: formattedDate(Date()), duration: "0:15"),
            RecordingData(title: "Carrer dels Ametllers, 9 23", date: "14 Apr 2024", duration: "0:10"),
            RecordingData(title: "Ark Hills 2", date: "4 Oct 2023", duration: "0:06"),
            RecordingData(title: "Ark Hills", date: "4 Oct 2023", duration: "0:04"),
            RecordingData(title: "Carrer dels Ametllers, 9 22", date: "23 Feb 2023", duration: "0:31"),
            RecordingData(title: "Carrer dels Ametllers, 9 21", date: "23 Feb 2023", duration: "0:30"),
            RecordingData(title: "Carrer dels Ametllers, 9 20", date: "9 Feb 2023", duration: "0:27"),
            RecordingData(title: "Carrer dels Ametllers, 9 19", date: "9 Feb 2023", duration: "0:28")
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
                    print("VoiceMemosView: Failed to override output port to speaker: \\(error.localizedDescription)")
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

    private var baseURL = "http://192.168.1.51:5002" // Changed to Mac's IP
    private var fallbackURLs: [String] = [] // Removed fallback to 0.0.0.0 for now
    private let apiKey = "test_api_key" // Replace with your actual API key if needed

    enum ConnectionStatus {
        case unknown
        case connected
        case failed
    }
    
    func verifyAPIKey() async throws -> Bool {
        // Try the primary URL first
        do {
            let result = try await verifyAPIWithURL(baseURL)
            // No need for DispatchQueue.main.async here anymore because the whole class is @MainActor
            self.connectionStatus = .connected
            return result
        } catch {
            print("Primary URL failed: \(error.localizedDescription)")
            
            // If primary URL fails, try fallbacks
            for fallbackURL in fallbackURLs {
                print("Primary URL failed, trying fallback: \(fallbackURL)")
                do {
                    let result = try await verifyAPIWithURL(fallbackURL)
                    // No need for DispatchQueue.main.async here anymore
                    self.connectionStatus = .connected
                    return result
                } catch {
                    print("Fallback URL \(fallbackURL) failed: \(error.localizedDescription)")
                }
            }
            
            // If all URLs fail, update status and throw error
            // No need for DispatchQueue.main.async here anymore
            self.connectionStatus = .failed
            throw NetworkError.connectionFailed
        }
    }
    
    private func verifyAPIWithURL(_ urlString: String) async throws -> Bool {
        guard let url = URL(string: "\(urlString)/verify-api") else {
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
        } catch {
            print("Primary URL failed for thought generation: \(error.localizedDescription)")
            
            // Try fallbacks
            for fallbackURL in fallbackURLs {
                do {
                    return try await generateThoughtWithURL(fallbackURL, topic: topic, value: value)
                } catch {
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
        
        // Create a URLRequest to have more control over the request
        var request = URLRequest(url: url)
        request.timeoutInterval = 15 // Set a reasonable timeout
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid HTTP response")
                throw NetworkError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMsg = errorJson["error"] as? String {
                    print("Server error: \(errorMsg)")
                    throw NetworkError.serverError(message: errorMsg)
                }
                throw NetworkError.serverError(message: "Unknown server error")
            }
            
            do {
                let thoughtResponse = try JSONDecoder().decode(ThoughtResponse.self, from: data)
                return thoughtResponse.thought
            } catch {
                print("JSON decoding error: \(error)")
                // Try to extract the message directly from the JSON
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let thought = json["thought"] as? String {
                    return thought
                }
                throw NetworkError.decodingError
            }
        } catch {
            print("Network error during thought generation: \(error.localizedDescription)")
            throw error
        }
    }
    
    func generateAudioWithClonedVoice(topic: String, value: String, stability: Double = 0.7, similarityBoost: Double = 0.85, addBackground: Bool = true, backgroundVolume: Double = 0.5) async throws -> Data { // Added addBackground and backgroundVolume with defaults
        // Try primary URL first
        do {
            return try await generateAudioWithURL(baseURL, topic: topic, value: value, stability: stability, similarityBoost: similarityBoost, addBackground: addBackground, backgroundVolume: backgroundVolume)
        } catch {
            print("Primary URL failed for audio generation: \(error.localizedDescription)")
            
            // Try fallbacks
            for fallbackURL in fallbackURLs {
                do {
                    return try await generateAudioWithURL(fallbackURL, topic: topic, value: value, stability: stability, similarityBoost: similarityBoost, addBackground: addBackground, backgroundVolume: backgroundVolume)
                } catch {
                    print("Fallback URL \(fallbackURL) failed for audio generation: \(error.localizedDescription)")
                }
            }
            // If all URLs fail, throw the error
            throw error
        }
    }
    
    private func generateAudioWithURL(_ urlString: String, topic: String, value: String, stability: Double, similarityBoost: Double, addBackground: Bool, backgroundVolume: Double) async throws -> Data { // Added addBackground and backgroundVolume
        // First, generate the thought
        let thought = try await generateThoughtWithURL(urlString, topic: topic, value: value)
        
        print("Generated thought: \(thought)")
        
        // Now send request to generate audio from that thought
        guard let url = URL(string: "\(urlString)/generate-audio") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30 // Set a longer timeout for audio generation
        
        // Include the thought, topic, value, and background sound parameters in the request
        let requestBody: [String: Any] = [
            "text": thought, // Assuming the backend expects the generated thought as 'text'
            "topic": topic,
            "value": value,
            "stability": stability,
            "similarity_boost": similarityBoost,
            "add_background": addBackground, // Pass to backend
            "background_volume": backgroundVolume // Pass to backend
        ]
        
        print("Sending request to Python backend with: \(requestBody)")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid HTTP response")
                throw NetworkError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                if let errorData = String(data: data, encoding: .utf8) {
                    print("Server error: \(errorData)")
                    throw NetworkError.serverError(message: errorData)
                }
                throw NetworkError.serverError(message: "Unknown server error")
            }
            
            print("Successfully received MP3 data from server: \(data.count) bytes")
            return data
        } catch {
            print("Network error during audio generation: \(error.localizedDescription)")
            throw error
        }
    }
}



// MARK: - Response Models
struct ThoughtResponse: Codable {
    let thought: String
}

// MARK: - Error Types
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(message: String)
    case decodingError
    case connectionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        case .decodingError:
            return "Error decoding server response"
        case .connectionFailed:
            return "Failed to connect to the server. Please ensure the Python backend is running."
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
            print("AudioManager: Failed to override output port to speaker: \\(error.localizedDescription)")
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
    let selectedButton: String
    let inputText: String
    @ObservedObject var apiManager: VoiceAPIManager // Changed to ObservedObject and passed in
    let onBackTapped: (RecordingData?) -> Void
    
    @State private var topic = ""
    @State private var value = ""
    @State private var generatedText = ""
    @State private var stability: Double = 0.7
    @State private var similarityBoost: Double = 0.85
    @State private var addBackground = false
    @State private var backgroundVolume: Double = 0.2
    
    @State private var isLoading = false
    @State private var lastGenerationTask: Task<Void, Never>? = nil
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var generatedAudioData: Data?
    @State private var showDocumentPicker = false
    @State private var selectedAudioFile: Data?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Navigation Header
                    HStack {
                        Button(action: { onBackTapped(createGeneratedRecording()) }) {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.blue)
                                Text("Back")
                                    .font(.system(size: 17))
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Spacer()
                        
                        Text("AI Voice Cloning")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button("Done") {
                            onBackTapped(createGeneratedRecording())
                        }
                        .font(.system(size: 17))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Connection status indicator
                    connectionStatusView
                    
                    headerView
                    infoView
                    textInputSection
                    advancedSettingsSection
                    regenerateButton // Added for re-generation
                    
                    if isLoading { // This is EditScreenView's own isLoading
                        loadingView
                    }
                    
                    if let audioData = generatedAudioData {
                        resultView(audioData: audioData)
                    }
                }
                .padding()
            }
            .background(Color.black)
            .onAppear {
                self.topic = selectedButton // Initialize topic from passed prop
                self.value = inputText    // Initialize value from passed prop
            }
            .task {
                // Directly call apiManager's method and handle potential error
                do {
                    let isValid = try await apiManager.verifyAPIKey()
                    if !isValid {
                        // Consider how to display this error, perhaps using existing showErrorAlert
                        // For now, just printing. If EditScreenView has its own error display, use that.
                        print("EditScreenView: API Key is invalid or verification failed.")
                        // You might want to set a local error state here if EditScreenView needs to react.
                        // Example: showErrorAlert("API Key is invalid or verification failed.")
                    }
                } catch {
                    print("EditScreenView: Could not verify API key: \\\\(error.localizedDescription)")
                    // Example: showErrorAlert("Could not verify API key: \\\\(error.localizedDescription)")
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // Create a RecordingData object from the generated audio
    private func createGeneratedRecording() -> RecordingData? {
        guard let audioData = generatedAudioData else { return nil }
        
        return RecordingData(
            title: "AI Generated: \\\\(topic) - \\\\(value)",
            date: formattedDate(Date()), // Call local/passed formattedDate
            duration: estimateDuration(from: audioData), // Call local/passed estimateDuration
            audioData: audioData
        )
    }
    
    // Added helper function
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    // Helper function to estimate duration
    private func estimateDuration(from audioData: Data) -> String {
        do {
            let player = try AVAudioPlayer(data: audioData)
            let seconds = Int(player.duration)
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        } catch {
            // Similar logic as in ContentView's estimateDuration
            let bytesPerSecondEstimate = 32000 // For 16-bit mono audio at 16kHz
            let estimatedSeconds = audioData.count / bytesPerSecondEstimate
            return "\(estimatedSeconds / 60):\(String(format: "%02d", estimatedSeconds % 60))"
        }
    }
    
    // MARK: - View Components
    private var connectionStatusView: some View {
        HStack {
            if apiManager.connectionStatus == .connected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connected to backend server")
                    .foregroundColor(.green)
            } else if apiManager.connectionStatus == .failed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Failed to connect to backend server")
                    .foregroundColor(.red)
            } else {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Checking connection...")
                    .foregroundColor(.gray)
            }
        }
        .font(.caption)
        .padding(.vertical, 5)
    }
    
    private var headerView: some View {
        VStack {
            Text("🎤 AI Voice Generation")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white) // Ensure white text for dark background
        }
    }
    
    private var infoView: some View { // Updated info text
        VStack(alignment: .leading, spacing: 8) {
            Text("Adjust Settings & Re-generate:")
                .font(.headline)
                .foregroundColor(.blue)
            
            Text("The initial audio was generated automatically. Use the settings below to fine-tune parameters like voice similarity and stability. Tap 'Re-generate Audio' to apply changes.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Topic for thought:")
                    .font(.headline)
                
                TextField("E.g., personal fears, movies, general", text: $topic)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: topic) { _ in
                        generateThoughtIfReady()
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Valor específico del tema:")
                    .font(.headline)
                
                TextField("E.g., spiders, Star Wars, today's weather", text: $value)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: value) { _ in
                        generateThoughtIfReady()
                    }
                    .overlay(
                        autoGenerationState == .generatingThought || autoGenerationState == .generatingAudio ?
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .padding(.trailing, 8)
                            } : nil
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Texto que quieres que diga la IA (generado):")
                    .font(.headline)
                
                TextEditor(text: $generatedText)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .disabled(true)
                    .overlay(
                        ZStack {
                            // Mostrar un mensaje si no hay texto generado
                            if generatedText.isEmpty && (topic.isEmpty || value.isEmpty) {
                                Text("Completa el tema y valor para generar texto")
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                    )
            }
        }
    }
    
    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Advanced settings to improve results:")
                .font(.headline)
                .foregroundColor(.blue)
            
            VStack(spacing: 15) {
                // Similarity slider
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Voice similarity:")
                        Spacer()
                        Text(String(format: "%.2f", similarityBoost))
                            .fontWeight(.bold)
                    }
                    
                    Slider(value: $similarityBoost, in: 0.5...1.0, step: 0.05)
                        .tint(.blue)
                }
                
                // Stability slider
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Stability:")
                        Spacer()
                        Text(String(format: "%.2f", stability))
                            .fontWeight(.bold)
                    }
                    
                    Slider(value: $stability, in: 0.3...1.0, step: 0.05)
                        .tint(.blue)
                }
                
                Text("👍 Increase similarity for a sound more like your voice. Increase stability for more consistent speech.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Background sound settings
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Add background sound (fan.mp3)", isOn: $addBackground)
                        .fontWeight(.medium)
                    
                    if addBackground {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Background volume:")
                                Spacer()
                                Text(String(format: "%.2f", backgroundVolume))
                                    .fontWeight(.bold)
                            }
                            
                            Slider(value: $backgroundVolume, in: 0.0...1.0, step: 0.05)
                                .tint(.blue)
                        }
                        
                        Text("🔊 Adjust background sound volume. 0 = very low, 1 = normal volume.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
    }
    
    private var generateButton: some View {
        Button("🚀 Generar Audio con IA") {
            generateAudio()
        }
        .foregroundColor(.white)
        .font(.headline)
        .padding()
        .frame(maxWidth: .infinity)
        .background(canGenerate ? Color.blue : Color.gray)
        .cornerRadius(10)
        .disabled(!canGenerate || isLoading)
    }
    
    private var loadingView: some View {
        VStack(spacing: 15) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Entrenando la IA con tu voz y generando el audio...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                
            Text("Esto puede tardar unos segundos")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }
    
    private func resultView(audioData: Data) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("✅ Audio generado exitosamente!")
                .font(.headline)
                .foregroundColor(.green)
            
            Text("Your audio has been generated with the cloned voice:")
                .foregroundColor(.secondary)
            
            AudioPlayerView(audioData: audioData)
            
            ShareLink(item: audioData, preview: SharePreview("Audio clonado", image: Image(systemName: "waveform"))) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Compartir Audio")
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Computed Properties
    // Removed: private var canGenerate: Bool { ... }
    
    // MARK: - Helper Methods
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    private func generateThoughtIfReady() {
        guard !topic.isEmpty && !value.isEmpty else {
            generatedText = ""
            autoGenerationState = .idle
            return
        }
        
        Task {
            do {
                let thought = try await apiManager.generateThought(topic: topic, value: value)
                await MainActor.run {
                    generatedText = thought
                    print("Successfully generated thought: \(thought)")
                }
            } catch {
                await MainActor.run {
                    showErrorAlert("Error al generar el pensamiento: \(error.localizedDescription)")
                    print("Error generating thought: \(error)")
                }
            }
        }
    }
    
    private func generateAudio() {
        guard canGenerate else { return }
        
        // Ensure we have the required parameters to generate audio
        guard !topic.isEmpty, !value.isEmpty, !generatedText.isEmpty else {
            showErrorAlert("Por favor, asegúrese de que el tema y el valor están definidos")
            return
        }
        
        isLoading = true
        print("Generando audio con topic: \(topic), value: \(value)")
        
        Task {
            do {
                let result = try await apiManager.generateAudioWithClonedVoice(
                    topic: self.topic, // Use local state topic
                    value: self.value, // Use local state value
                    stability: stability,
                    similarityBoost: similarityBoost
                )
                
                await MainActor.run {
                    generatedAudioData = result // Update EditScreenView's audio data
                    isLoading = false
                    print("Successfully received audio data: \(result.count) bytes")
                    
                    // Opcionalmente podemos reproducir el audio automáticamente aquí
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    showErrorAlert("Error al generar audio: \(error.localizedDescription)")
                    print("Error generating audio: \(error)")
                }
            }
        }
    }
    
    private func verifyAPI() async {
        do {
            let isValid = try await apiManager.verifyAPIKey()
            if !isValid {
                await MainActor.run {
                    showErrorAlert("❌ API Key inválida. Por favor verifica tu configuración del servidor.")
                }
            }
        }
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
                print("AudioPlayerView: Failed to override output port to speaker: \\(error.localizedDescription)")
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

