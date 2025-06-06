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
else
    source venv/bin/activate
fi

# Start the Python server
echo "Starting server on http://localhost:5002"
python3 main.py
