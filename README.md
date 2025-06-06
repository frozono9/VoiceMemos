# Swift App with Python Backend Integration

## Overview
This project consists of:
1. A Swift iOS/macOS app for voice memo recording and AI voice cloning
2. A Python backend that handles the AI thought generation and voice synthesis

## How to Run the System

### Step 1: Start the Python Backend
1. Open Terminal
2. Navigate to the `prebaalex` directory
3. Run the start script:
```bash
cd /Users/nicolasrosales/Desktop/prebaalex
./start_backend.sh
```
4. The server will start on http://localhost:5002

### Step 2: Run the Swift App
1. Open the Xcode project at `/Users/nicolasrosales/Documents/GitHub/VoiceMemos/Voice Memos/Voice Memos.xcodeproj`
2. Build and run the app on your device or simulator
3. Follow these steps in the app:
   - Select a category (e.g., "Movies", "Phobias", etc.)
   - Enter a value related to that category
   - In the Edit screen, enter a topic and value to generate a thought
   - Press "Generate Audio with AI" to get the synthesized audio

## How It Works
1. The Swift app sends the topic and value to the Python backend via `/generate-thought` endpoint
2. The backend uses AI to generate a natural-sounding thought based on the inputs
3. When generating audio, the app sends the topic and value to the backend via `/generate-audio` endpoint
4. The Python backend uses the pre-recorded `cloningvoice.mp3` to create a cloned voice for the generated thought
5. The resulting MP3 is sent back to the Swift app and played to the user

## Troubleshooting
- Ensure the Python server is running before using the Swift app
- Check that your environment variables (ELEVEN_LABS_API_KEY and GOOGLE_API_KEY) are set correctly
- For local development, ensure your device/simulator can connect to localhost
