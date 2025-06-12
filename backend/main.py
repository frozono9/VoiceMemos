import os
import tempfile
import requests
import json
import traceback
import jwt # Added for JWT
import bcrypt # Added for password hashing
import certifi # Added for MongoDB SSL
from flask import Flask, request, send_file, jsonify, render_template, g
from dotenv import load_dotenv
from pydub import AudioSegment
import google.generativeai as genai
from google.generativeai.client import configure
from pymongo import MongoClient
from bson import ObjectId
from email_validator import validate_email, EmailNotValidError
import re
from datetime import datetime, timedelta # Added timedelta
from functools import wraps # Added for decorator

load_dotenv()
API_KEY = os.getenv("ELEVEN_LABS_API_KEY")
if not API_KEY:
    raise RuntimeError("ELEVEN_LABS_API_KEY not set in environment")

# Configure Google Gemini API
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
if not GOOGLE_API_KEY:
    print("WARNING: GOOGLE_API_KEY not set in environment. Thought generation will not work.")
else:
    # Initialize Google Gemini API
    try:
        # Assuming 'configure' is from 'google.generativeai.client' as per original context
        from google.generativeai.client import configure
        configure(api_key=GOOGLE_API_KEY)
        print("Google AI client initialized successfully")
    except ImportError:
        print("Failed to import 'google.generativeai.client.configure'. Make sure the library is installed.")
        traceback.print_exc()
    except Exception as e:
        print(f"Error initializing Google AI client: {e}")
        traceback.print_exc()

# Define Gemini model name
GOOGLE_MODEL_NAME = "gemini-2.0-flash" # Updated to a common model, ensure this is intended

# ElevenLabs model configuration
ELEVENLABS_DEFAULT_MODEL = os.getenv("ELEVENLABS_MODEL", "eleven_multilingual_v2")
ELEVENLABS_TURBO_MODEL = os.getenv("ELEVENLABS_TURBO_MODEL", "eleven_turbo_v2_5")

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024  # 50 MB límite para archivos grandes
app.config['JWT_SECRET_KEY'] = os.getenv("JWT_SECRET_KEY", "your-super-secret-jwt-key-fallback") # Added JWT Secret Key
# Enable CORS for all routes
from flask_cors import CORS
CORS(app)

# MongoDB Setup
MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017/")

# Add certifi to the MongoDB client connection
client = MongoClient(MONGO_URI, tlsCAFile=certifi.where())

db = client.voicememos_db # Database name
users_collection = db.users
activation_codes_collection = db.activation_codes

# Create indexes for unique fields
users_collection.create_index("username", unique=True)
users_collection.create_index("email", unique=True)
activation_codes_collection.create_index("code", unique=True)

# Decorator for JWT requirement
def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        if 'Authorization' in request.headers:
            auth_header = request.headers['Authorization']
            try:
                token = auth_header.split(" ")[1]
            except IndexError:
                return jsonify({"message": "Bearer token malformed"}), 401

        if not token:
            return jsonify({"message": "Token is missing!"}), 401

        try:
            # Decode the token using the app's secret key
            data = jwt.decode(token, app.config['JWT_SECRET_KEY'], algorithms=["HS256"])

            # Fetch the user from DB and store in flask.g
            current_user = users_collection.find_one({"_id": ObjectId(data["user_id"])})
            if not current_user:
                return jsonify({"message": "User not found for token"}), 401
            g.current_user = current_user

        except jwt.ExpiredSignatureError:
            return jsonify({"message": "Token has expired!"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"message": "Token is invalid!"}), 401
        except Exception as e:
            print(f"Token validation error: {e}")
            traceback.print_exc()
            return jsonify({"message": "Token processing error"}), 401

        return f(*args, **kwargs)
    return decorated

# URLs para la API de Eleven Labs
ELEVEN_VOICE_ADD_URL = "https://api.elevenlabs.io/v1/voices/add"
ELEVEN_TTS_URL_TEMPLATE = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"

# Cabeceras para la API de Eleven Labs
headers = {
    "xi-api-key": API_KEY
}

# Variable global para almacenar el ID de la voz de Alex Latorre
ALEX_LATORRE_VOICE_ID = None

def get_available_models():
    """Get available TTS models from ElevenLabs"""
    try:
        models_resp = requests.get("https://api.elevenlabs.io/v1/models", headers=headers)
        models_resp.raise_for_status()
        models_data = models_resp.json()
        
        print("Available ElevenLabs models:")
        for model in models_data.get('models', []):
            model_id = model.get('model_id', 'unknown')
            name = model.get('name', 'Unknown')
            description = model.get('description', 'No description')
            print(f"  - ID: {model_id}, Name: {name}")
            print(f"    Description: {description}")
        
        return models_data.get('models', [])
    except requests.exceptions.RequestException as e:
        print(f"Error fetching models from ElevenLabs: {e}")
        return []
    except Exception as e:
        print(f"An unexpected error occurred while fetching models: {e}")
        return []

def get_alex_latorre_voice_id():
    """Obtiene el voice_id de 'Alex Latorre' de Eleven Labs."""
    global ALEX_LATORRE_VOICE_ID
    if ALEX_LATORRE_VOICE_ID:
        return ALEX_LATORRE_VOICE_ID

    try:
        voices_resp = requests.get("https://api.elevenlabs.io/v1/voices", headers=headers)
        voices_resp.raise_for_status()
        voices_data = voices_resp.json()
        
        for voice in voices_data.get('voices', []):
            if voice.get('name', '').lower() == 'alex latorre': # Case-insensitive comparison
                ALEX_LATORRE_VOICE_ID = voice.get('voice_id')
                print(f"Found voice 'Alex Latorre' with ID: {ALEX_LATORRE_VOICE_ID}")
                return ALEX_LATORRE_VOICE_ID
        
        print("ERROR: Voice 'Alex Latorre' not found in your ElevenLabs account.")
        print("Available voices:")
        for voice in voices_data.get('voices', []):
            print(f"  - Name: {voice.get('name')}, ID: {voice.get('voice_id')}, Category: {voice.get('category')}")
        return None
    except requests.exceptions.RequestException as e:
        print(f"Error fetching voices from ElevenLabs: {e}")
        return None
    except Exception as e:
        print(f"An unexpected error occurred while fetching voice ID: {e}")
        return None

# Llama a la función al iniciar la aplicación para obtener el ID de la voz
# Esto se ejecutará una vez cuando el servidor Flask comience.
ALEX_LATORRE_VOICE_ID = get_alex_latorre_voice_id()

# Also get available models on startup
print("\n" + "="*50)
print("ELEVENLABS MODELS INFORMATION")
print("="*50)
available_models = get_available_models()
print("="*50 + "\n")

def verify_api_key():
    """Verify that the API key is valid by making a test request to Eleven Labs"""
    try:
        response = requests.get("https://api.elevenlabs.io/v1/models", headers=headers)
        response.raise_for_status()
        return True
    except requests.exceptions.RequestException as e:
        print(f"API Key verification failed: {e}")
        return False

@app.route('/')
def index():
    return render_template('index_new.html')

@app.route('/verify-api', methods=['GET'])
def verify_api():
    """Endpoint to verify API key status"""
    if verify_api_key():
        return jsonify({"status": "success", "message": "API key is valid"})
    else:
        return jsonify({"status": "error", "message": "API key is invalid"}), 401

@app.route('/models', methods=['GET'])
def get_models():
    """Endpoint to get available ElevenLabs models"""
    models = get_available_models()
    if models:
        return jsonify({"models": models}), 200
    else:
        return jsonify({"error": "Failed to fetch models"}), 500

def _is_likely_inappropriate(text):
    """Check if text contains potentially inappropriate content"""
    if not text:
        return False
        
    text = text.lower()
    inappropriate_patterns = [
        'sex', 'porn', 'nude', 'naked', 'xxx', 'dildo', 'vibrator', 'nsfw',
        'fuck', 'shit', 'ass', 'dick', 'cock', 'pussy', 'cunt', 'whore',
        'bitch', 'slut', 'horny', 'masturbat', 'orgas', 'nazi', 'kill', 
        'murder', 'suicide', 'rape', 'racist', 'n-word', 'nigger'
    ]
    
    return any(pattern in text for pattern in inappropriate_patterns)

def _generate_thought_text(prompt, topic, value, language="english"): # Added language parameter
    """Genera texto usando la API de Gemini en el idioma especificado."""
    
    # Determine the appropriate starting phrase based on language
    start_phrase = "Okay, so..."
    fallback_message_template = "Okay, so... This morning I had a feeling that someone I know is interested in {value} regarding {topic}."
    if language.lower().startswith("es") or language.lower() == "spanish":
        start_phrase = "Okay, entonces..." # Or a more natural Spanish equivalent
        fallback_message_template = "Okay, entonces... Esta mañana tuve la sensación de que alguien que conozco está interesado en {value} en relación a {topic}."

    if not GOOGLE_API_KEY:
        print(f"GOOGLE_API_KEY not set. Returning fallback message in {language}.")
        return fallback_message_template.format(value=value, topic=topic)
    
    try:
        # Attempt to use the Google AI Python SDK
        try:
            from google.generativeai.generative_models import GenerativeModel # Original import
            model = GenerativeModel(GOOGLE_MODEL_NAME)
            
            # Construct the full prompt including the language-specific start_phrase instruction
            # The main prompt content is passed as 'prompt' argument to this function
            full_prompt_for_gemini = f"{prompt}" # The 'prompt' arg already contains language instructions

            thought_response = model.generate_content(full_prompt_for_gemini)
            
            generated_text = ""
            if hasattr(thought_response, 'text'):
                generated_text = thought_response.text.strip()
            elif hasattr(thought_response, 'candidates') and thought_response.candidates:
                candidate = thought_response.candidates[0]
                if hasattr(candidate, 'content') and hasattr(candidate.content, 'parts') and candidate.content.parts:
                    if hasattr(candidate.content.parts[0], 'text'):
                        generated_text = candidate.content.parts[0].text.strip()

            return generated_text

        except (ImportError, NameError, AttributeError) as sdk_err:
            print(f"Google AI SDK error or not available: {str(sdk_err)}. Falling back to REST API or general fallback.")
            traceback.print_exc()
        
        # Fallback to REST API if SDK fails (optional, or remove if SDK is primary)
        # For simplicity, if SDK fails, we'll use the general fallback here.
        # If REST API fallback is desired, it would be implemented here similar to original code.

    except Exception as e:
        print(f"Error generating text with Gemini: {e}")
        traceback.print_exc()
    
    # General fallback if all attempts fail
    print(f"All Gemini generation attempts failed. Returning fallback message in {language}.")
    return fallback_message_template.format(value=value, topic=topic)


@app.route('/generate-audio-cloned', methods=['POST'])
@token_required
def generate_audio():
    """Endpoint para generar audio. Soporta form-data (HTML) y JSON (Swift app)."""
    topic_str = None
    value_str = None
    
    # Default values for voice settings
    stability_val = g.current_user.get("settings", {}).get("stability", 0.7)
    similarity_boost_val = g.current_user.get("settings", {}).get("voice_similarity", 0.85)
    user_language = g.current_user.get("settings", {}).get("language", "english") 

    if request.is_json:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Request body must be valid JSON if Content-Type is application/json"}), 400
        
        topic_str = data.get('topic')
        value_str = data.get('value')
        
        # Allow numbers directly from JSON for these settings, or strings that can be converted
        stability_input = data.get('stability', stability_val) # Use user's default if not provided
        similarity_boost_input = data.get('similarity_boost', similarity_boost_val) # Use user's default

        try:
            stability_val = float(stability_input)
            similarity_boost_val = float(similarity_boost_input)
        except (ValueError, TypeError):
            return jsonify({"error": "Los parámetros 'stability' y 'similarity_boost' deben ser números válidos"}), 400

    else:  # Fallback to form data
        if 'topic' not in request.form or 'value' not in request.form:
            # Check if it's an empty form submission or truly missing params
            if not request.form:
                 return jsonify({"error": "Unsupported Media Type or missing data. Use application/json or form-data."}), 415
            return jsonify({"error": "Se requieren los parámetros 'topic' y 'value' (form-data)"}), 400

        topic_str = request.form.get('topic')
        value_str = request.form.get('value')
        
        stability_form_str = request.form.get('stability', str(stability_val))
        similarity_boost_form_str = request.form.get('similarity_boost', str(similarity_boost_val))
        try:
            stability_val = float(stability_form_str)
            similarity_boost_val = float(similarity_boost_form_str)
        except ValueError:
            return jsonify({"error": "Los parámetros 'stability' y 'similarity_boost' (form-data) deben ser números válidos"}), 400

    if not topic_str or not isinstance(topic_str, str) or not topic_str.strip():
        return jsonify({"error": "'topic' es requerido, debe ser un string no vacío y no puede consistir solo de espacios"}), 400
    if not value_str or not isinstance(value_str, str) or not value_str.strip():
        return jsonify({"error": "'value' es requerido, debe ser un string no vacío y no puede consistir solo de espacios"}), 400
    
    topic = topic_str.strip()
    value = value_str.strip()

    try:
        user_clone_id = g.current_user.get("voice_clone_id")
        voice_id_to_use = user_clone_id if user_clone_id else (ALEX_LATORRE_VOICE_ID or get_alex_latorre_voice_id())
        
        if not voice_id_to_use:
            username = g.current_user.get("username", "user")
            return jsonify({"error": f"Voice clone for '{username}' not found and default voice unavailable. Please check backend logs."}), 500

        # Determine prompt start phrase and fallback text based on language
        prompt_start_phrase = "Okay, so..."
        inappropriate_fallback_text = "This morning I woke up thinking about how interesting magic is and how it can surprise people."
        if user_language.lower().startswith("es") or user_language.lower() == "spanish":
            prompt_start_phrase = "Okay, entonces..." # Or "Bueno, pues..." or "A ver..."
            inappropriate_fallback_text = "Esta mañana me desperté pensando en lo interesante que es la magia y cómo puede sorprender a la gente."


        if _is_likely_inappropriate(topic) or _is_likely_inappropriate(value):
            generated_text = inappropriate_fallback_text
            print(f"Warning: Potentially inappropriate content detected. Using safe fallback in {user_language}.")
        else:
            # Construct the safe_prompt with language instructions for Gemini
            safe_prompt = f"""
──────────  ROLE  ──────────
You are a fully awake person who just got ready for the day — and you're recording a quick, casual voice note in {user_language}.  
You suddenly remembered a weird dream, or had a strange passing thought, and you want to say it out loud before you forget.

────────  MUST‑HAVES  ────────
1. **Language**: The entire note must be in {user_language}.  
2. **Tone**: Awake, calm, and casual — like you're talking to yourself or a friend in the morning.  
3. **Value inclusion**: The value **({value})** should be mentioned naturally by name, not forced.  
4. **Topic as subtext**: Do **NOT** mention the topic **({topic})** — but let it guide the general mood or situation.  
5. **Length**: One or two short sentences — max 15 seconds to read aloud.  
6. **Emotion**: Curious, chill, or a bit puzzled — no drama or exaggeration. Think: “I just remembered something odd.”

────────  STYLE TIPS  ────────
• Use conversational, natural speech for {user_language} — like how people talk out loud in the morning.  
• Feel free to use a few filler words typical for the language (e.g., “no sé”, “o algo”, “creo”, “genre”, “je pense”, “kinda”, etc.).  
• Avoid sounding too polished — contractions and incomplete thoughts are fine.  
• Keep punctuation relaxed — ellipses, commas, or nothing at all.  

────────  EXAMPLES (adjust to {user_language})  ────────
EN:  “I was brushing my teeth and suddenly remembered this weird dream… someone was terrified of spiders, like legit panic. No idea why it came back to me.”  
ES:  “Estaba ya vistiéndome y me vino esta imagen rarísima… alguien hablaba de arañas y se ponía super nervioso, no sé qué fue eso.”  
FR:  “J’étais prêt à sortir et là, paf, j’me souviens d’un truc dans mon rêve… un mec flippait grave à cause des araignées. C’est revenu d’un coup.”  
DE:  “Ich war schon fertig im Bad und plötzlich kam so ein Bild aus dem Traum hoch… irgendwer hatte mega Angst vor Spinnen. Ganz seltsam.”  
IT:  “Stavo per uscire e all’improvviso mi è tornata in mente questa scena… qualcuno parlava dei ragni e sembrava super agitato. Boh.”

────────  OUTPUT RULE  ────────
Return only the voice note in {user_language}, no additional text, labels, or formatting.
"""
            generated_text = _generate_thought_text(safe_prompt, topic, value, user_language)

        print(f"Texto generado ({user_language}): {generated_text}")

        tts_url = ELEVEN_TTS_URL_TEMPLATE.format(voice_id=voice_id_to_use)
        
        # ElevenLabs model selection - choose the model that best fits your needs
        # Available models (as of 2024):
        # - "eleven_multilingual_v2" (default) - Best for multiple languages, high quality
        # - "eleven_turbo_v2" - Faster generation, good quality, lower latency
        # - "eleven_turbo_v2_5" - Latest turbo model with improvements
        # - "eleven_monolingual_v1" - English only, high quality
        # - "eleven_multilingual_v1" - Older multilingual model
        
        # ElevenLabs model selection - choose the model that best fits your needs
        # Available models (as of 2024):
        # - "eleven_multilingual_v2" (default) - Best for multiple languages, high quality
        # - "eleven_turbo_v2" - Faster generation, good quality, lower latency
        # - "eleven_turbo_v2_5" - Latest turbo model with improvements
        # - "eleven_monolingual_v1" - English only, high quality
        # - "eleven_multilingual_v1" - Older multilingual model
        
        # Always use Eleven Turbo v2.5 model
        model_id = ELEVENLABS_TURBO_MODEL  # Always use turbo model for fast generation
        
        print(f"Using ElevenLabs model: {model_id} (Eleven Turbo v2.5) for language: {user_language}")
        
        json_payload = {
            "text": generated_text,
            "model_id": model_id,  # Add model selection
            "voice_settings": {
                "stability": stability_val,
                "similarity_boost": similarity_boost_val
            }
            # Language for ElevenLabs TTS is typically tied to the voice model,
            # especially for cloned voices or specific multilingual pre-made voices.
            # The text itself being in the target language is key.
        }

        print(f"Generando TTS con voice_id: {voice_id_to_use}, texto (primeros 100 chars): '{generated_text[:100]}...', settings: {json_payload['voice_settings']}, language context from user: {user_language}")
        tts_resp = requests.post(tts_url, headers={**headers, 'Content-Type': 'application/json'}, json=json_payload)

        try:
            tts_resp.raise_for_status()
        except requests.HTTPError as e:
            error_msg = f"Error al generar voz: {tts_resp.text}"
            print(f"ERROR TTS: {error_msg}") # Differentiate TTS error log
            return jsonify({"error": error_msg}), tts_resp.status_code

        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as out:
            out.write(tts_resp.content)
            out_path = out.name

        # Schedule deletion of the temp file after sending it
        # This requires a bit more setup (e.g., Flask's after_this_request) or handling it differently
        # For now, it's deleted when the 'with' block for NamedTemporaryFile would normally end if delete=True
        # Since it's delete=False, it persists. Consider a cleanup strategy for these files.

        return send_file(out_path, mimetype='audio/mpeg', as_attachment=True, download_name='output.mp3')

    except Exception as e:
        print(f"Error general en generate_audio: {e}")
        traceback.print_exc()
        return jsonify({"error": f"Error al generar audio: {str(e)}"}), 500

# --- User Authentication Endpoints ---

def is_valid_email(email):
    try:
        validate_email(email)
        return True
    except EmailNotValidError:
        return False

@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400

    username = data.get('username')
    email = data.get('email')
    password = data.get('password')
    activation_code_str = data.get('activation_code')

    if not all([username, email, password, activation_code_str]):
        return jsonify({"error": "Missing username, email, password, or activation_code"}), 400

    if not is_valid_email(email):
        return jsonify({"error": "Invalid email format"}), 400

    # Validate activation code
    activation_code = activation_codes_collection.find_one({"code": activation_code_str})
    if not activation_code:
        return jsonify({"error": "Invalid activation code"}), 400
    if activation_code.get("used"):
        return jsonify({"error": "Activation code already used"}), 400

    # Check for existing user
    if users_collection.find_one({"username": username}):
        return jsonify({"error": "Username already exists"}), 409 # 409 Conflict
    if users_collection.find_one({"email": email}):
        return jsonify({"error": "Email already exists"}), 409

    hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
    
    # Default user settings
    default_settings = {
        "language": "english", # Default language
        "voice_similarity": 0.85,
        "stability": 0.70,
        "add_background_sound": True, # NEW
        "background_volume": 0.5      # NEW
    }

    user_data = {
        "username": username,
        "email": email,
        "password": hashed_password,
        "created_at": datetime.utcnow(),
        "settings": default_settings, # Add default settings
        "voice_clone_id": None, # Initialize voice_clone_id
        "voice_ids": [], # Initialize voice_ids list for multiple cloned voices
        "loggedIn": False # Initialize as not logged in
    }
    
    try:
        result = users_collection.insert_one(user_data)
        # Mark activation code as used
        activation_codes_collection.update_one(
            {"_id": activation_code['_id']},
            {"$set": {"used": True, "used_by": result.inserted_id, "used_at": datetime.utcnow()}}
        )
        return jsonify({"message": "User registered successfully", "user_id": str(result.inserted_id)}), 201
    except Exception as e:
        print(f"Error during user registration: {e}")
        traceback.print_exc()
        return jsonify({"error": "Registration failed due to a server error"}), 500

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400

    email_or_username = data.get('email') # Swift client sends 'email' field for email/username
    password = data.get('password')

    if not email_or_username or not password:
        return jsonify({"error": "Missing email/username or password"}), 400

    # Try to find user by email or username
    user = users_collection.find_one({"$or": [{"email": email_or_username}, {"username": email_or_username}]})

    if user and bcrypt.checkpw(password.encode('utf-8'), user['password']):
        # Check if user is already logged in
        if user.get('loggedIn', False):
            return jsonify({"error": "User is already logged in from another device. Please sign out from the other device first."}), 409
        
        # Password matches and user is not logged in elsewhere, generate JWT
        token_payload = {
            'user_id': str(user['_id']),
            'username': user['username'],
            'exp': datetime.utcnow() + timedelta(hours=24)  # Token expires in 24 hours
        }
        try:
            token = jwt.encode(token_payload, app.config['JWT_SECRET_KEY'], algorithm='HS256')
            
            # Set loggedIn to True
            users_collection.update_one(
                {"_id": user['_id']}, 
                {"$set": {"loggedIn": True}}
            )
            
            return jsonify({"message": "Login successful", "token": token}), 200
        except Exception as e:
            print(f"Error generating token: {e}")
            return jsonify({"error": "Failed to generate token"}), 500
    else:
        return jsonify({"error": "Invalid credentials"}), 401

@app.route('/verify-activation-code', methods=['POST'])
def verify_activation_code_endpoint():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400
    
    code_str = data.get('code')
    if not code_str:
        return jsonify({"error": "Missing 'code' parameter"}), 400

    activation_code = activation_codes_collection.find_one({"code": code_str})

    if not activation_code:
        return jsonify({"valid": False, "message": "Activation code not found"}), 404
    
    if activation_code.get("used"):
        return jsonify({"valid": False, "message": "Activation code has already been used"}), 200 # Or 400/409 depending on desired behavior

    return jsonify({"valid": True, "message": "Activation code is valid"}), 200

# Endpoint to generate a voice clone from user audio
@app.route('/generate-voice-clone', methods=['POST'])
@token_required
def generate_voice_clone():
    overwrite = request.values.get('overwrite', 'false').strip().lower() in ('true', '1')
    existing_id = g.current_user.get('voice_clone_id')
    user_language_setting = g.current_user.get("settings", {}).get("language", "english")

    # Map app language name to ElevenLabs language codes
    # (Refer to ElevenLabs documentation for the full list of supported codes: https://elevenlabs.io/docs/speech-synthesis/voice-cloning#supported-languages)
    lang_code_map = {
        "english": "en", "spanish": "es", "french": "fr", "german": "de",
        "italian": "it", "portuguese": "pt", "polish": "pl", "hindi": "hi",
        "arabic": "ar", "japanese": "ja", "chinese": "zh", "korean": "ko",
        "dutch": "nl", "turkish": "tr", "swedish": "sv", "indonesian": "id",
        "filipino": "fil", "vietnamese": "vi", "ukrainian": "uk", "greek": "el",
        "czech": "cs", "finnish": "fi", "romanian": "ro", "danish": "da",
        "bulgarian": "bg", "malay": "ms", "slovak": "sk", "croatian": "hr",
        "classic arabic": "ar", # Example if specific variants needed
        "tamil": "ta", "russian": "ru" # Added Russian
    }
    elevenlabs_lang_code = lang_code_map.get(user_language_setting.lower(), "en") # Default to 'en'
    print(f"User language for cloning: {user_language_setting}, mapped to ElevenLabs code: {elevenlabs_lang_code}")

    if existing_id and not overwrite:
        return jsonify({"voice_clone_id": existing_id, "message": "Existing voice clone ID returned."}), 200
    
    if existing_id and overwrite:
        delete_url = f"https://api.elevenlabs.io/v1/voices/{existing_id}"
        try:
            del_resp = requests.delete(delete_url, headers=headers)
            del_resp.raise_for_status()
            print(f"Successfully deleted old voice clone {existing_id} for user {g.current_user.get('username')}")
            users_collection.update_one({"_id": g.current_user['_id']}, {"$unset": {"voice_clone_id": ""}})
        except requests.exceptions.RequestException as e:
            print(f"Failed to delete old voice clone {existing_id} from ElevenLabs: {e}. Proceeding to create a new one.")

    if 'audio' not in request.files:
        return jsonify({"error": "Missing 'audio' file"}), 400
    
    file = request.files['audio']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    temp_file_path = None
    opened_file_for_request = None # To ensure it's closed

    try:
        # Validate audio file (basic check, more robust validation might be needed)
        # Pydub can be heavy; consider alternatives if only simple validation is needed.
        # For now, assume the file is reasonably valid if it gets this far.
        # audio_seg = AudioSegment.from_file(file) 
        # if len(audio_seg) > 5 * 60 * 1000: # Max 5 minutes for cloning
        #     return jsonify({"error": "Audio file is too long. Maximum 5 minutes allowed for cloning."}), 400
        # file.seek(0) 

        with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename)[1]) as temp:
            file.save(temp.name)
            temp_file_path = temp.name
        
        opened_file_for_request = open(temp_file_path, 'rb')
        files_for_request = [('files', (file.filename, opened_file_for_request, file.mimetype))]

        # The 'language' parameter for /v1/voices/add is NOT standard for v1 cloning.
        # Language is typically inferred from the audio.
        # However, some newer ElevenLabs models or Professional Voice Cloning might use it.
        # For standard v1 cloning, it's safer to omit it if not explicitly supported or rely on audio content.
        # If the API supports it and it's beneficial, it can be added.
        # The name and description can hint at the language.
        data_payload = {
            "name": f"{g.current_user['username']}_{elevenlabs_lang_code}", 
            "description": f"Voice clone for user {g.current_user['username']} (Language: {user_language_setting} - {elevenlabs_lang_code})",
            "labels": '{}', # Must be a JSON string
            # "language": elevenlabs_lang_code # Add this if confirmed supported & beneficial for your ElevenLabs plan/version
        }
        # If your ElevenLabs setup *requires* the language field for cloning, uncomment the line above.
        # Otherwise, the language of the audio files themselves is the primary determinant.

        print(f"Attempting to clone voice. Name: {data_payload['name']}. Audio language should be {user_language_setting}.")
        resp = requests.post(ELEVEN_VOICE_ADD_URL, headers=headers, files=files_for_request, data=data_payload)
        resp.raise_for_status()
        
        voice_data = resp.json()
        voice_id = voice_data.get('voice_id')
        if not voice_id:
            print(f"No 'voice_id' returned from ElevenLabs. Response: {voice_data}")
            return jsonify({"error": "No 'voice_id' returned from ElevenLabs"}), 500

        users_collection.update_one({"_id": g.current_user['_id']}, {"$set": {"voice_clone_id": voice_id}})
        
        result = {"voice_clone_id": voice_id, "message": "Voice clone created successfully."}
        return jsonify(result), 200

    except requests.HTTPError as e:
        error_body = resp.text if resp and hasattr(resp, 'text') else "No response body"
        status_code = e.response.status_code if hasattr(e, 'response') else 500
        print(f"ElevenLabs API HTTPError during cloning: {status_code} - {error_body}")
        return jsonify({"error": f"ElevenLabs API error: {error_body}"}), status_code
    except Exception as e:
        print(f"Error during voice clone: {e}")
        traceback.print_exc()
        return jsonify({"error": f"Failed to create voice clone: {str(e)}"}), 500
    finally:
        if opened_file_for_request:
            opened_file_for_request.close()
        if temp_file_path and os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except Exception as e:
                print(f"Error deleting temp file {temp_file_path}: {e}")

# Add endpoint to fetch current user info
@app.route('/me', methods=['GET'])
@token_required
def me():
    user = g.current_user
    if not user:
        return jsonify({"error": "User not found"}), 404

    # Ensure settings exist and have all default fields if some are missing
    user_settings = user.get("settings", {})
    
    # Define complete default settings structure
    default_settings_template = {
        "language": "english",
        "voice_similarity": 0.85, # Ensure this matches UserSettings in Swift if it's persisted
        "stability": 0.70,
        "add_background_sound": True,
        "background_volume": 0.5,
        "voice_ids": user.get("voice_ids", []) # Include voice_ids from user document
    }

    # Merge user_settings with defaults, giving priority to user_settings
    # This ensures all keys from default_settings_template are present
    final_settings = {**default_settings_template, **user_settings}
    # Ensure voice_ids is correctly sourced from the main user document, not potentially overwritten by a stale settings object
    final_settings["voice_ids"] = user.get("voice_ids", [])


    return jsonify({
        "user_id": str(user["_id"]),
        "username": user["username"],
        "email": user["email"],
        "settings": final_settings, # Return merged settings
        "voice_clone_id": user.get("voice_clone_id"), # Keep this for compatibility if needed
        "voice_ids": user.get("voice_ids", []) # Ensure this is directly from user doc
    }), 200

@app.route('/delete-voice-clone', methods=['DELETE'])
@token_required
def delete_voice_clone():
    user = g.current_user
    existing_id = user.get('voice_clone_id')
    
    if not existing_id:
        return jsonify({"error": "No voice clone found to delete"}), 404
    
    # Delete voice clone from ElevenLabs
    delete_url = f"https://api.elevenlabs.io/v1/voices/{existing_id}"
    try:
        del_resp = requests.delete(delete_url, headers=headers)
        del_resp.raise_for_status()
        print(f"Deleted voice clone {existing_id} for user {user.get('username')}")
    except Exception as e:
        print(f"Failed to delete voice clone {existing_id}: {e}")
        return jsonify({"error": f"Failed to delete voice clone from ElevenLabs: {str(e)}"}), 500
    
    # Remove voice_clone_id from user document in MongoDB
    users_collection.update_one(
        {"_id": user['_id']}, 
        {"$unset": {"voice_clone_id": ""}}
    )
    
    return jsonify({"message": "Voice clone deleted successfully"}), 200

@app.route('/update-settings', methods=['POST'])
@token_required
def update_settings():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400

    user = g.current_user
    if not user:
        return jsonify({"error": "User not found"}), 404

    current_settings = user.get("settings", {})
    updated_fields = {}

    # Language
    if 'language' in data:
        lang = data['language']
        if not isinstance(lang, str) or lang not in ["english", "spanish"]: # Add more valid languages as needed
            return jsonify({"error": "Invalid language value"}), 400
        updated_fields["settings.language"] = lang

    # Voice Similarity
    if 'voice_similarity' in data:
        similarity = data['voice_similarity']
        try:
            similarity_float = float(similarity)
            if not (0.0 <= similarity_float <= 1.0):
                raise ValueError("Similarity must be between 0.0 and 1.0")
            updated_fields["settings.voice_similarity"] = similarity_float
        except (ValueError, TypeError):
            return jsonify({"error": "Invalid voice_similarity value. Must be a float between 0.0 and 1.0."}), 400

    # Stability
    if 'stability' in data:
        stability = data['stability']
        try:
            stability_float = float(stability)
            if not (0.0 <= stability_float <= 1.0):
                raise ValueError("Stability must be between 0.0 and 1.0")
            updated_fields["settings.stability"] = stability_float
        except (ValueError, TypeError):
            return jsonify({"error": "Invalid stability value. Must be a float between 0.0 and 1.0."}), 400
            
    # Add Background Sound
    if 'add_background_sound' in data:
        add_bg_sound = data['add_background_sound']
        if not isinstance(add_bg_sound, bool):
            return jsonify({"error": "Invalid add_background_sound value. Must be a boolean."}), 400
        updated_fields["settings.add_background_sound"] = add_bg_sound

    # Background Volume
    if 'background_volume' in data:
        bg_volume = data['background_volume']
        try:
            bg_volume_float = float(bg_volume)
            if not (0.0 <= bg_volume_float <= 1.0):
                raise ValueError("Background volume must be between 0.0 and 1.0")
            updated_fields["settings.background_volume"] = bg_volume_float
        except (ValueError, TypeError):
            return jsonify({"error": "Invalid background_volume value. Must be a float between 0.0 and 1.0."}), 400

    if not updated_fields:
        return jsonify({"message": "No settings provided to update.", "settings": current_settings}), 200

    try:
        users_collection.update_one({"_id": user["_id"]}, {"$set": updated_fields})
        # Fetch the updated user document to return the latest settings
        updated_user = users_collection.find_one({"_id": user["_id"]})
        
        # Prepare the settings to be returned, ensuring defaults for any missing fields
        final_settings = {
            "language": "english",
            "voice_similarity": 0.85,
            "stability": 0.70,
            "add_background_sound": True,
            "background_volume": 0.5,
            "voice_ids": updated_user.get("voice_ids", []) # Ensure voice_ids is included
        }
        # Merge the actually updated settings from DB
        if updated_user and "settings" in updated_user:
            final_settings.update(updated_user["settings"])
        
        return jsonify({"message": "Settings updated successfully", "settings": final_settings}), 200
    except Exception as e:
        print(f"Error updating settings: {e}")
        traceback.print_exc()
        return jsonify({"error": "Failed to update settings due to a server error"}), 500

@app.route('/logout', methods=['POST'])
@token_required
def logout():
    """Endpoint to log out the current user and set loggedIn to false"""
    try:
        # Set loggedIn to False for the current user
        users_collection.update_one(
            {"_id": g.current_user['_id']}, 
            {"$set": {"loggedIn": False}}
        )
        
        return jsonify({"message": "Logged out successfully"}), 200
    except Exception as e:
        print(f"Error during logout: {e}")
        traceback.print_exc()
        return jsonify({"error": "Failed to log out due to a server error"}), 500

# Configuration for CORS and next endpoints ... existing code ...
@app.after_request
def after_request(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response

if __name__ == '__main__':
    # Puerto 5002 para evitar conflictos
    app.run(host='0.0.0.0', port=5002, debug=True)
