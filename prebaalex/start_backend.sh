#!/bin/bash

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Please install it and try again."
    exit 1
fi

# Navigate to the backend directory
cd "$(dirname "$0")"

# Setup or activate virtual environment
if [ ! -d "venv" ]; then
    echo "Setting up virtual environment..."
    python3 -m venv venv
fi

# Activate the virtual environment
source venv/bin/activate

# Upgrade pip and install dependencies
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

# Check if pymongo is installed
if ! python3 -c "import pymongo" &> /dev/null; then
    echo "Error: pymongo not found in the virtual environment." >&2
    echo "Please check that requirements.txt includes 'pymongo' and try again." >&2
    exit 1
fi

# Install ffmpeg if not already installed (required by pydub)
if ! command -v ffmpeg &> /dev/null; then
    echo "Installing ffmpeg..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install ffmpeg
    else
        sudo apt-get update && sudo apt-get install -y ffmpeg
    fi
fi

# Start the Python server using venv Python
echo "Starting server on http://localhost:5002"
echo "Make sure your Swift app is configured to connect to http://localhost:5002 or http://127.0.0.1:5002"
venv/bin/python3 main.py

