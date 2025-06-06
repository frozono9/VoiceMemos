#!/bin/bash

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Please install it and try again."
    exit 1
fi

# Navigate to the backend directory
cd "$(dirname "$0")"

# Check if requirements are installed and install them if not
if [ ! -d "venv" ]; then
    echo "Setting up virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    
    # Install ffmpeg if not already installed (required by pydub)
    if ! command -v ffmpeg &> /dev/null; then
        echo "Installing ffmpeg..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            brew install ffmpeg
        else
            # Linux
            sudo apt-get update && sudo apt-get install -y ffmpeg
        fi
    fi
else
    source venv/bin/activate
fi

# Check if .env file exists, create it if not
if [ ! -f ".env" ]; then
    echo "Creating .env file..."
    echo "ELEVEN_LABS_API_KEY=your_api_key_here" > .env
    echo "GOOGLE_API_KEY=your_api_key_here" >> .env
    echo "Please edit the .env file and add your API keys."
fi

# Check if cloningvoice.mp3 exists, create a placeholder if not
if [ ! -f "cloningvoice.mp3" ]; then
    echo "Creating placeholder cloningvoice.mp3 file..."
    echo "This is a placeholder file. Please replace with a real MP3 file." > cloningvoice.mp3
    echo "Please replace the placeholder cloningvoice.mp3 with a real MP3 file."
fi

# Start the Python server
echo "Starting server on http://localhost:5002"
echo "Make sure your Swift app is configured to connect to http://localhost:5002 or http://127.0.0.1:5002"
python3 main.py

