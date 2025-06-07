import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import CoreHaptics // Ensure CoreHaptics is imported, though UIImpactFeedbackGenerator is in UIKit

struct ContentView: View {
    @State private var selectedButton: String = ""
    @State private var inputText: String = ""
    @State private var currentScreen: AppScreen = .home // Ensure initial screen is .home
    @State private var generatedRecording: RecordingData? = nil
    @StateObject private var apiManager = VoiceAPIManager() // Added
    @State private var generationError: String? = nil // Added for error display

    enum AppScreen {
        case buttonSelection
        case textInput
        case voiceMemos
        case editScreen
        case home // Added home screen case
        case tutorial // Added tutorial screen case
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
                        // currentScreen = .editScreen // OLD
                        currentScreen = .home       // NEW: Navigate to Home
                    }
                )
            case .editScreen:
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
            case .home: // Handle home screen
                NavigationView { // Added NavigationView
                    HomeScreenView(
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
                        }
                    )
                    .navigationTitle("Voice Memos AI") // Added title
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
                print("ContentView: Starting audio generation with topic: \\(selectedButton), value: \\(inputText)")
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
                        title: "Error: \\(selectedButton) - \\(inputText.prefix(20))...",
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
    let onPerformTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onTutorialTapped: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea() // Dark background consistent with other views

            VStack(spacing: 25) { // Adjusted spacing
                Spacer()

                Button(action: onPerformTapped) {
                    HStack(spacing: 10) { // Added spacing for icon and text
                        Image(systemName: "waveform.path.ecg")
                            .font(.title2) // Match text font size or slightly larger
                        Text("Perform")
                            .fontWeight(.medium)
                    }
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: 280, minHeight: 60) // Adjusted size
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12) // Slightly more rounded
                }

                Button(action: onSettingsTapped) {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape.fill") // Changed icon to filled
                            .font(.title2)
                        Text("Settings")
                            .fontWeight(.medium)
                    }
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: 280, minHeight: 60)
                    .background(Color.secondary) // Changed to a more standard settings color
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                Button(action: onTutorialTapped) {
                    HStack(spacing: 10) {
                        Image(systemName: "book.fill") // Changed icon to filled
                            .font(.title2)
                        Text("Tutorial")
                            .fontWeight(.medium)
                    }
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: 280, minHeight: 60)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                Spacer()
                Spacer() // More space at the bottom
            }
        }
        // .navigationTitle("Voice Memos AI") // This is set on the NavigationView in ContentView
    }
}

struct TutorialView: View {
    let onBackTapped: () -> Void // Action to go back

    var body: some View {
        ScrollView { // Added ScrollView for potentially longer content
            VStack(alignment: .leading, spacing: 15) { // Adjusted spacing
                
                Text("Welcome to Voice Memos AI!")
                    .font(.title) // Larger title
                    .fontWeight(.bold)
                    .padding(.bottom, 10)

                Text("Follow these steps to create your AI voice memo:")
                    .font(.headline)
                    .padding(.bottom, 5)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Tap 'Perform' on the Home screen.", systemImage: "1.circle")
                    Label("Select a topic category (e.g., 'Cards', 'Movies') or choose 'Custom'.", systemImage: "2.circle")
                    Label("Enter specific text related to your chosen topic.", systemImage: "3.circle")
                    Label("The app will then generate a short voice memo.", systemImage: "4.circle")
                    Label("Find your new memo at the top of the 'All Recordings' list.", systemImage: "5.circle")
                    Label("Tap on any memo to reveal playback controls.", systemImage: "6.circle")
                }
                .font(.body)
                
                Spacer(minLength: 20) // Add some space before the next section

                Text("Additional Info:")
                    .font(.headline)
                    .padding(.bottom, 5)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("The 'Settings' screen (accessed from Home) shows advanced options. Currently, the AI voice is fixed.", systemImage: "gearshape.fill")
                    Label("Generated audio is dated as 'yesterday' for this version.", systemImage: "calendar.badge.clock")
                }
                .font(.body)

            }
            .padding()
        }
        .navigationTitle("How to Use") // Set title here
        .navigationBarTitleDisplayMode(.inline) // Prefer inline for sub-screens
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { // Changed to .navigationBarTrailing for "Done"
                Button("Done") {
                    onBackTapped()
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
            RecordingData(title: "Carrer dels Ametllers, 9 24", date: "18 May 2025", duration: "0:15"),
            RecordingData(title: "2024-14-04", date: "14 Apr 2024", duration: "0:12"),
            RecordingData(title: "Strange Dream 01", date: "2 Apr 2024", duration: "0:09"),
            RecordingData(title: "Dream 11", date: "21 Mar 2024", duration: "0:07"),
            RecordingData(title: "Dream 10", date: "8 Mar 2024", duration: "0:31"),
            RecordingData(title: "Strange Dream 02", date: "22 Feb 2024", duration: "0:30"),
            RecordingData(title: "Dream 09", date: "10 Feb 2024", duration: "0:27"),
            // Generate a static array of
            RecordingData(title: "Strange Dream 03", date: "15 Jan 2024", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Dream 07", date: "2 Jan 2024", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Dream 06", date: "19 Dec 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Dream 05", date: "7 Dec 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Strange Dream 04", date: "23 Nov 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Dream 04", date: "10 Nov 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Dream 03", date: "29 Oct 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Strange Dream 05", date: "14 Oct 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Dream 02", date: "2 Oct 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Dream 01", date: "20 Sep 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "Strange Dream 06", date: "8 Sep 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "2023-08-25", date: "25 Aug 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "2023-08-13", date: "13 Aug 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "2023-07-31", date: "31 Jul 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "2023-07-17", date: "17 Jul 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "2023-07-03", date: "3 Jul 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "2023-06-18", date: "18 Jun 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))"),
            RecordingData(title: "2023-06-05", date: "5 Jun 2023", duration: "\(Int.random(in: 0...0)):\(String(format: "%02d", Int.random(in: 5...35)))")
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

    // Added settings properties
    @Published var stability: Double = 0.7
    @Published var similarityBoost: Double = 0.85
    @Published var addBackground: Bool = true
    @Published var backgroundVolume: Double = 0.5


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
    
    // Modified to use stored settings, removed default parameters for them
    func generateAudioWithClonedVoice(topic: String, value: String) async throws -> Data {
        // Try primary URL first
        do {
            return try await generateAudioWithURL(baseURL,
                                                topic: topic,
                                                value: value,
                                                stability: self.stability, // Use stored value
                                                similarityBoost: self.similarityBoost, // Use stored value
                                                addBackground: self.addBackground, // Use stored value
                                                backgroundVolume: self.backgroundVolume) // Use stored value
        } catch {
            print("Primary URL failed for audio generation: \\(error.localizedDescription)")
            
            // Try fallbacks
            for fallbackURL in fallbackURLs {
                do {
                    return try await generateAudioWithURL(fallbackURL,
                                                        topic: topic,
                                                        value: value,
                                                        stability: self.stability,
                                                        similarityBoost: self.similarityBoost,
                                                        addBackground: self.addBackground,
                                                        backgroundVolume: self.backgroundVolume)
                } catch {
                    print("Fallback URL \\(fallbackURL) failed for audio generation: \\(error.localizedDescription)")
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
    // Removed selectedButton and inputText
    @ObservedObject var apiManager: VoiceAPIManager
    let onBackTapped: () -> Void // MODIFIED: No longer takes RecordingData?
    
    // Removed @State variables related to text input, generation, loading, and results
    @State private var showError = false // KEEP for API verification
    @State private var errorMessage = "" // KEEP for API verification
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Navigation Header
                    HStack {
                        Button(action: { onBackTapped() }) { // MODIFIED: Call onBackTapped without params
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
                        
                        Text("Settings") // MODIFIED: Title changed
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button("Done") {
                            onBackTapped() // MODIFIED: Call onBackTapped without params
                        }
                        .font(.system(size: 17))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    connectionStatusView // KEEP
                    
                    // headerView, infoView, textInputSection, generateButton, loadingView, resultView REMOVED
                    
                    advancedSettingsSection // KEEP (will bind to apiManager)
                }
                .padding()
            }
            .background(Color.black)
            // .onAppear block REMOVED
            .task {
                await performAPIVerification()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // createGeneratedRecording(), formattedDate(), estimateDuration() REMOVED
    
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
    
    // headerView REMOVED
    // infoView REMOVED
    // textInputSection REMOVED
    
    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Advanced settings to improve results:")
                .font(.headline)
                .foregroundColor(.blue)
            
            VStack(spacing: 15) {
                // Similarity slider - BIND TO apiManager
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Voice similarity:")
                        Spacer()
                        Text(String(format: "%.2f", apiManager.similarityBoost)) // Use apiManager
                            .fontWeight(.bold)
                    }
                    Slider(value: $apiManager.similarityBoost, in: 0.5...1.0, step: 0.05) // Use apiManager
                        .tint(.blue)
                }
                
                // Stability slider - BIND TO apiManager
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Stability:")
                        Spacer()
                        Text(String(format: "%.2f", apiManager.stability)) // Use apiManager
                            .fontWeight(.bold)
                    }
                    Slider(value: $apiManager.stability, in: 0.3...1.0, step: 0.05) // Use apiManager
                        .tint(.blue)
                }
                
                Text("👍 Increase similarity for a sound more like your voice. Increase stability for more consistent speech.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Background sound settings - BIND TO apiManager
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Add background sound (fan.mp3)", isOn: $apiManager.addBackground) // Use apiManager
                        .fontWeight(.medium)
                    
                    if apiManager.addBackground { // Use apiManager
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Background volume:")
                                Spacer()
                                Text(String(format: "%.2f", apiManager.backgroundVolume)) // Use apiManager
                                    .fontWeight(.bold)
                            }
                            Slider(value: $apiManager.backgroundVolume, in: 0.0...1.0, step: 0.05) // Use apiManager
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
    
    // generateButton, loadingView, resultView REMOVED
    // canGenerate, formatTime REMOVED
    
    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    // generateThoughtIfReady(), generateAudio() REMOVED
    
    private func performAPIVerification() async {
        do {
            let isValid = try await apiManager.verifyAPIKey()
            if !isValid {
                // Ensure UI updates are on the main actor, though showErrorAlert might handle this
                await MainActor.run {
                    showErrorAlert("API Key is invalid or verification failed.")
                }
                print("EditScreenView: API Key is invalid or verification failed.")
            }
        } catch {
            await MainActor.run {
                showErrorAlert("Could not verify API key: \\(error.localizedDescription)")
            }
            print("EditScreenView: Could not verify API key: \\(error.localizedDescription)")
        }
    }
    
    // verifyAPI() REMOVED
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

