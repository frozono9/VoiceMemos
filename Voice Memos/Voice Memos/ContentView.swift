import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct VoiceMemosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var selectedButton: String = ""
    @State private var inputText: String = ""
    @State private var currentScreen: AppScreen = .buttonSelection
    
    enum AppScreen {
        case buttonSelection
        case textInput
        case voiceMemos
        case editScreen
    }
    
    var body: some View {
        switch currentScreen {
        case .buttonSelection:
            ButtonSelectionView(selectedButton: $selectedButton) {
                currentScreen = .textInput
            }
        case .textInput:
            TextInputView(inputText: $inputText) {
                currentScreen = .voiceMemos
            }
        case .voiceMemos:
            VoiceMemosView(
                selectedButton: selectedButton,
                inputText: inputText,
                onEditTapped: {
                    currentScreen = .editScreen
                }
            )
        case .editScreen:
            EditScreenView(
                selectedButton: selectedButton,
                inputText: inputText,
                onBackTapped: {
                    currentScreen = .voiceMemos
                }
            )
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
            Color.black.ignoresSafeArea()
            
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
                            .background(Color.gray.opacity(0.3))
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
            Color.black.ignoresSafeArea()
            
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

struct VoiceMemosView: View {
    let selectedButton: String
    let inputText: String
    let onEditTapped: () -> Void
    
    @State private var showingPeek = false
    @State private var showingSiriPrompt = false
    @State private var selectedRecording: RecordingData? = nil
    @State private var isPlaying = false
    @State private var currentTime = 0.0
    @State private var totalTime = 15.0
    
    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
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
                            let recordings = [
                                RecordingData(title: "Carrer dels Ametllers, 9 24", date: formattedDate(Date()), duration: "0:15"),
                                RecordingData(title: "Carrer dels Ametllers, 9 23", date: "14 Apr 2024", duration: "0:10"),
                                RecordingData(title: "Ark Hills 2", date: "4 Oct 2023", duration: "0:06"),
                                RecordingData(title: "Ark Hills", date: "4 Oct 2023", duration: "0:04"),
                                RecordingData(title: "Carrer dels Ametllers, 9 22", date: "23 Feb 2023", duration: "0:31"),
                                RecordingData(title: "Carrer dels Ametllers, 9 21", date: "23 Feb 2023", duration: "0:30"),
                                RecordingData(title: "Carrer dels Ametllers, 9 20", date: "9 Feb 2023", duration: "0:27"),
                                RecordingData(title: "Carrer dels Ametllers, 9 19", date: "9 Feb 2023", duration: "0:28")
                            ]
                            
                            ForEach(recordings.indices, id: \.self) { index in
                                VStack(spacing: 0) {
                                    RecordingRow(
                                        recording: recordings[index],
                                        isSelected: selectedRecording?.title == recordings[index].title,
                                        isPlaying: isPlaying,
                                        currentTime: currentTime,
                                        totalTime: totalTime,
                                        onTap: { recording in
                                            if selectedRecording?.title == recording.title {
                                                selectedRecording = nil
                                            } else {
                                                selectedRecording = recording
                                                totalTime = parseDuration(recording.duration)
                                                currentTime = 0
                                                isPlaying = false
                                            }
                                        },
                                        onPlay: { togglePlayback() },
                                        onDelete: { selectedRecording = nil }
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
    
    private func togglePlayback() {
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
class VoiceAPIManager: ObservableObject {
    private let baseURL = "YOUR_SERVER_URL" // Replace with your server URL
    
    func verifyAPIKey() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/verify-api") else {
            throw NetworkError.invalidURL
        }
        
        let (_, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        return httpResponse.statusCode == 200
    }
    
    func generateThought(topic: String, value: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/generate-thought?topic=\(topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&value=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NetworkError.serverError
        }
        
        let thoughtResponse = try JSONDecoder().decode(ThoughtResponse.self, from: data)
        return thoughtResponse.thought
    }
    
    func generateVoiceClone(request: VoiceGenerationRequest) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/generate") else {
            throw NetworkError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let formData = createMultipartFormData(boundary: boundary, request: request)
        urlRequest.httpBody = formData
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NetworkError.serverError
        }
        
        return data
    }
    
    private func createMultipartFormData(boundary: String, request: VoiceGenerationRequest) -> Data {
        var formData = Data()
        
        // Audio file
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        formData.append(request.audioData)
        formData.append("\r\n".data(using: .utf8)!)
        
        // Text
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"text\"\r\n\r\n".data(using: .utf8)!)
        formData.append(request.text.data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        
        // Parameters
        let parameters = [
            "stability": String(request.stability),
            "similarity_boost": String(request.similarityBoost),
            "add_background": String(request.addBackground),
            "bg_volume": String(request.backgroundVolume)
        ]
        
        for (key, value) in parameters {
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            formData.append(value.data(using: .utf8)!)
            formData.append("\r\n".data(using: .utf8)!)
        }
        
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return formData
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
    case serverError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL inválida"
        case .invalidResponse:
            return "Respuesta inválida del servidor"
        case .serverError:
            return "Error del servidor"
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
            return "Permiso de micrófono denegado"
        case .recordingFailed:
            return "Error al grabar audio"
        case .playbackFailed:
            return "Error al reproducir audio"
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
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

// MARK: - Edit Screen View
struct EditScreenView: View {
    let selectedButton: String
    let inputText: String
    let onBackTapped: () -> Void
    
    @StateObject private var audioManager = AudioManager()
    @StateObject private var apiManager = VoiceAPIManager()
    
    @State private var topic = ""
    @State private var value = ""
    @State private var generatedText = ""
    @State private var stability: Double = 0.7
    @State private var similarityBoost: Double = 0.85
    @State private var addBackground = false
    @State private var backgroundVolume: Double = 0.2
    
    @State private var isLoading = false
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
                        Button(action: onBackTapped) {
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
                            onBackTapped()
                        }
                        .font(.system(size: 17))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    headerView
                    infoView
                    audioInputSection
                    textInputSection
                    advancedSettingsSection
                    generateButton
                    
                    if isLoading {
                        loadingView
                    }
                    
                    if let audioData = generatedAudioData {
                        resultView(audioData: audioData)
                    }
                }
                .padding()
            }
            .background(Color.black)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { data in
                selectedAudioFile = data
                audioManager.hasRecording = false // Clear recording when file is selected
            }
        }
        .task {
            await verifyAPI()
        }
    }
    
    // MARK: - View Components
    private var headerView: some View {
        VStack {
            Text("🎤 AI Voice Cloning")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
    }
    
    private var infoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cómo funciona:")
                .font(.headline)
                .foregroundColor(.blue)
            
            Text("Graba tu voz por al menos 30 segundos (idealmente 2 minutos) o sube un archivo MP3, luego escribe el tema y valor para generar el texto que quieres que diga con tu voz clonada.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var audioInputSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Entrena tu voz:")
                .font(.headline)
            
            // Recording controls
            HStack(spacing: 15) {
                Button(action: {
                    if audioManager.isRecording {
                        audioManager.stopRecording()
                    } else {
                        Task {
                            do {
                                try await audioManager.startRecording()
                            } catch {
                                showErrorAlert(error.localizedDescription)
                            }
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        Text(audioManager.isRecording ? "Parar" : "Grabar Voz")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(audioManager.isRecording ? Color.red : Color.blue)
                    .cornerRadius(8)
                }
                
                if audioManager.isRecording {
                    Text(formatTime(audioManager.recordingTime))
                        .font(.monospaced(.body)())
                        .fontWeight(.bold)
                        .foregroundColor(audioManager.recordingTime >= 120 ? .green : 
                                       audioManager.recordingTime >= 30 ? .orange : .red)
                    
                    if audioManager.recordingTime >= 120 {
                        Text("✅")
                    }
                }
            }
            
            // Recording preview
            if audioManager.hasRecording {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tu grabación:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Button(action: {
                            if audioManager.isPlaying {
                                audioManager.stopPlayback()
                            } else {
                                do {
                                    try audioManager.playRecording()
                                } catch {
                                    showErrorAlert(error.localizedDescription)
                                }
                            }
                        }) {
                            Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title2)
                        }
                        
                        Text("Reproducir grabación")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            // File picker option
            Text("- O -")
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 10) {
                Button("📁 Seleccionar archivo de audio") {
                    showDocumentPicker = true
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(8)
                
                if selectedAudioFile != nil {
                    Text("✅ Archivo seleccionado")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
    
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tema para el pensamiento:")
                    .font(.headline)
                
                TextField("Ej: miedos personales, películas, general", text: $topic)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: topic) { _ in
                        generateThoughtIfReady()
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Valor específico del tema:")
                    .font(.headline)
                
                TextField("Ej: arañas, Star Wars, el clima de hoy", text: $value)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: value) { _ in
                        generateThoughtIfReady()
                    }
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
            }
        }
    }
    
    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Ajustes avanzados para mejorar resultados:")
                .font(.headline)
                .foregroundColor(.blue)
            
            VStack(spacing: 15) {
                // Similarity slider
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Similitud de voz:")
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
                        Text("Estabilidad:")
                        Spacer()
                        Text(String(format: "%.2f", stability))
                            .fontWeight(.bold)
                    }
                    
                    Slider(value: $stability, in: 0.3...1.0, step: 0.05)
                        .tint(.blue)
                }
                
                Text("👍 Aumenta la similitud para un sonido más parecido a tu voz. Aumenta la estabilidad para un habla más consistente.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Background sound settings
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Añadir sonido de fondo (fan.mp3)", isOn: $addBackground)
                        .fontWeight(.medium)
                    
                    if addBackground {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Volumen del fondo:")
                                Spacer()
                                Text(String(format: "%.2f", backgroundVolume))
                                    .fontWeight(.bold)
                            }
                            
                            Slider(value: $backgroundVolume, in: 0.0...1.0, step: 0.05)
                                .tint(.blue)
                        }
                        
                        Text("🔊 Ajusta el volumen del sonido de fondo. 0 = muy bajo, 1 = volumen normal.")
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
        }
        .padding()
    }
    
    private func resultView(audioData: Data) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("✅ Audio generado exitosamente!")
                .font(.headline)
                .foregroundColor(.green)
            
            Text("Tu audio ha sido generado con la voz clonada:")
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
    }
    
    // MARK: - Computed Properties
    private var canGenerate: Bool {
        (audioManager.hasRecording || selectedAudioFile != nil) && 
        !generatedText.isEmpty && 
        !topic.isEmpty && 
        !value.isEmpty
    }
    
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
            return
        }
        
        Task {
            do {
                let thought = try await apiManager.generateThought(topic: topic, value: value)
                await MainActor.run {
                    generatedText = thought
                }
            } catch {
                await MainActor.run {
                    showErrorAlert("Error al generar el pensamiento: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func generateAudio() {
        guard canGenerate else { return }
        
        let audioData: Data
        if let recordingData = audioManager.getRecordingData() {
            audioData = recordingData
        } else if let fileData = selectedAudioFile {
            audioData = fileData
        } else {
            showErrorAlert("No hay audio disponible")
            return
        }
        
        let request = VoiceGenerationRequest(
            audioData: audioData,
            text: generatedText,
            stability: stability,
            similarityBoost: similarityBoost,
            addBackground: addBackground,
            backgroundVolume: backgroundVolume
        )
        
        isLoading = true
        
        Task {
            do {
                let result = try await apiManager.generateVoiceClone(request: request)
                await MainActor.run {
                    generatedAudioData = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    showErrorAlert("Error al generar el audio: \(error.localizedDescription)")
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
        } catch {
            print("Could not verify API key: \(error)")
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
                        Text("Audio generado")
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

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentPicked: (Data) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentPicked: onDocumentPicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentPicked: (Data) -> Void
        
        init(onDocumentPicked: @escaping (Data) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            do {
                let data = try Data(contentsOf: url)
                onDocumentPicked(data)
            } catch {
                print("Error reading file: \(error)")
            }
        }
    }
}

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

struct RecordingData {
    let title: String
    let date: String
    let duration: String
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

