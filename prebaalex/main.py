import os
import tempfile
import requests
import json
import traceback
from flask import Flask, request, send_file, jsonify, render_template, g
from dotenv import load_dotenv
from pydub import AudioSegment
import google.generativeai as genai
from google.generativeai.client import configure
from pymongo import MongoClient
from bson import ObjectId
import bcrypt
from email_validator import validate_email, EmailNotValidError
import re
from datetime import datetime, timedelta # Added timedelta
import certifi
import jwt # Added for JWT
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
        configure(api_key=GOOGLE_API_KEY)
        print("Google AI client initialized successfully")
    except Exception as e:
        print(f"Error initializing Google AI client: {e}")
        traceback.print_exc()

# Define Gemini model name
GOOGLE_MODEL_NAME = "gemini-2.0-flash"

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

def _generate_thought_text(prompt, topic, value):
    """Genera texto usando la API de Gemini"""
    if not GOOGLE_API_KEY:
        return f"Esta mañana tuve la sensación de que alguien que conozco está interesado en {value} en relación a {topic}."
    
    try:
        # Intenta usar el SDK de Python primero
        try:
            from google.generativeai.generative_models import GenerativeModel
            model = GenerativeModel(GOOGLE_MODEL_NAME)
            
            try:
                thought_response = model.generate_content(prompt)
                
                if hasattr(thought_response, 'text'):
                    return thought_response.text.strip()
                else:
                    # Intenta extraer texto de candidates si está disponible
                    if hasattr(thought_response, 'candidates') and thought_response.candidates:
                        candidate = thought_response.candidates[0]
                        if hasattr(candidate, 'content') and hasattr(candidate.content, 'parts'):
                            parts = candidate.content.parts
                            if parts and hasattr(parts[0], 'text'):
                                return parts[0].text.strip()
            except Exception as sdk_ex:
                print(f"Error con Google AI SDK: {str(sdk_ex)}")
                traceback.print_exc()
        except (ImportError, NameError) as import_err:
            print(f"Error con SDK: {str(import_err)}")

        # Segunda opción: Usar REST API directamente
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{GOOGLE_MODEL_NAME}:generateContent?key={GOOGLE_API_KEY}"
        
        payload = {
            "contents": [{
                "parts": [{
                    "text": prompt
                }]
            }],
            "generationConfig": {
                "temperature": 0.7,
                "topK": 1,
                "topP": 0.8,
                "maxOutputTokens": 100,
                "stopSequences": []
            },
            "safetySettings": [
                {
                    "category": "HARM_CATEGORY_HARASSMENT",
                    "threshold": "BLOCK_ONLY_HIGH"
                },
                {
                    "category": "HARM_CATEGORY_HATE_SPEECH",
                    "threshold": "BLOCK_ONLY_HIGH"
                },
                {
                    "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                    "threshold": "BLOCK_ONLY_HIGH"
                },
                {
                    "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                    "threshold": "BLOCK_ONLY_HIGH"
                }
            ]
        }
        
        response = requests.post(
            url,
            headers={"Content-Type": "application/json"},
            json=payload
        )
        
        if response.status_code == 200:
            result = response.json()
            if "candidates" in result and len(result["candidates"]) > 0:
                if "content" in result["candidates"][0] and "parts" in result["candidates"][0]["content"]:
                    return result["candidates"][0]["content"]["parts"][0]["text"].strip()
    
    except Exception as e:
        print(f"Error generando texto: {e}")
        traceback.print_exc()
    
    # Fallback si falla todo
    return f"Esta mañana tuve la sensación de que alguien que conozco está interesado en {value} en relación a {topic}."

@app.route('/generate-audio-cloned', methods=['POST'])
@token_required
def generate_audio():
    """Endpoint para generar audio. Soporta form-data (HTML) y JSON (Swift app)."""
    topic_str = None
    value_str = None
    
    # Default values for voice settings
    stability_val = 0.7
    similarity_boost_val = 0.85

    if request.is_json:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Request body must be valid JSON if Content-Type is application/json"}), 400
        
        topic_str = data.get('topic')
        value_str = data.get('value')
        
        # Allow numbers directly from JSON for these settings, or strings that can be converted
        stability_input = data.get('stability', stability_val)
        similarity_boost_input = data.get('similarity_boost', similarity_boost_val)

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
        # Determine which voice ID to use: user's clone if available, otherwise default
        user_clone_id = g.current_user.get("voice_clone_id")
        if user_clone_id:
            voice_id_to_use = user_clone_id
        else:
            voice_id_to_use = ALEX_LATORRE_VOICE_ID or get_alex_latorre_voice_id()
        if not voice_id_to_use:
            username = g.current_user.get("username", "user")
            return jsonify({"error": f"Voice clone for '{username}' not found and default voice unavailable. Please check backend logs."}), 500

        # Generar el texto usando Gemini
        if _is_likely_inappropriate(topic) or _is_likely_inappropriate(value):
            generated_text = "This morning I woke up thinking about how interesting magic is and how it can surprise people."
            print(f"Warning: Potentially inappropriate content detected. Using safe fallback.")
        else:
            safe_prompt = f"""
Generate a short, natural voice note — like someone just woke up and is casually recording a weird dream or morning hunch. It should sound spontaneous and human, like the kind of thing you’d say out loud to yourself when you barely remember it.

It should include the value ({value}), but not in a forced way — just let it come up naturally, like it’s part of what they remembered from the dream. It shouldn’t directly mention the topic ({topic}), but it should influence the tone and content — think of it as the unspoken context.

Use real, messy language: hesitations, pauses, filler words like “uh,” “kinda,” “I think,” “or something.” The vibe should be loose, sleepy, and conversational. Don’t over-explain, pretty straight to the point. Don’t sound like you’re trying to be clever. Just like someone talking into their phone, half-awake. 

Tone: neutral or curious — like “maybe that means something…”

Length constraint: Keep it short enough that it would take no more than 10 seconds to say out loud.

Examples:
	•	“Okay, so I just woke up and had this random dream where this girl was freaking out about spiders. Like… not just scared, but full-on panic. No idea why that stuck.”
	•	“I dunno, I had this dream where someone was talking about going to Paris. Felt super real for some reason. Might hear it again today or something.”
	•	“Weird dream. Some guy was bragging about getting an A+ in math. I don’t even know who he was.”

Only return the voice note text. Nothing else. Always start with "Okay, so..."
"""
            generated_text = _generate_thought_text(safe_prompt, topic, value)

        print(f"Texto generado1: {generated_text}")

        # Ya no se clona la voz, se usa la existente.
        # El siguiente bloque de código para crear/clonar voz se elimina.
        # ----- INICIO BLOQUE ELIMINADO -----
        # # Usar el archivo cloningvoice.mp3 predefinido
        # audio_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cloningvoice.mp3")

        # # Verificar que el archivo existe
        # if not os.path.exists(audio_path):
        #     return jsonify({"error": "No se encontró el archivo de voz para clonar (cloningvoice.mp3)"}), 500

        # print(f"Usando archivo de voz: {audio_path}, tamaño: {os.path.getsize(audio_path)} bytes")

        # # Crear una nueva voz con el archivo de audio predefinido
        # with open(audio_path, 'rb') as f:
        #     file_content = f.read()

        #     files = {
        #         "files": (os.path.basename(audio_path), file_content, "audio/mpeg")
        #     }
        #     data = {
        #         "name": "predefined-voice", # Podrías cambiar este nombre si quieres
        #         "description": "Predefined voice for cloning",
        #         "labels": '{"accent": ""}', # Ajusta las etiquetas si es necesario
        #         "language": "es" # Ajusta el idioma si es necesario
        #     }

        #     resp = requests.post(ELEVEN_VOICE_ADD_URL, headers=headers, files=files, data=data)

        # print(f"Voice creation response status: {resp.status_code}")
        # print(f"Voice creation response: {resp.text}")

        # try:
        #     resp.raise_for_status()
        #     voice_data = resp.json()
        #     voice_id = voice_data.get('voice_id')

        #     if not voice_id:
        #         error_msg = f"No se recibió voice_id en respuesta exitosa: {resp.text}"
        #         print(f"ERROR: {error_msg}")
        #         return jsonify({"error": error_msg}), 500

        # except requests.HTTPError as e:
        #     if "voice_limit_reached" in resp.text:
        #         print("Se alcanzó el límite de voces. Intentando obtener la lista de voces existentes...")

        #         try:
        #             voices_resp = requests.get("https://api.elevenlabs.io/v1/voices", headers=headers)
        #             voices_resp.raise_for_status()
        #             voices = voices_resp.json()

        #             # Intenta encontrar una voz clonada existente o una específica si es necesario
        #             cloned_voices = [v for v in voices.get('voices', []) if v.get('category') == 'cloned'] # O busca por nombre

        #             if cloned_voices:
        #                 voice_id = cloned_voices[0].get('voice_id') # O la voz específica
        #                 print(f"Usando voz existente con ID: {voice_id}")
        #             else:
        #                 return jsonify({"error": "No hay voces disponibles y se alcanzó el límite de creación de voces"}), 500
        #         except Exception as ve:
        #             print(f"Error al obtener voces: {ve}")
        #             return jsonify({"error": "Error al obtener voces existentes"}), 500
        #     else:
        #         error_msg = f"Error HTTP {resp.status_code} de Eleven Labs API: {resp.text}"
        #         print(f"ERROR: {error_msg}")
        #         return jsonify({"error": error_msg}), resp.status_code
        
        # if not voice_id: # Safeguard
        #      return jsonify({"error": "Failed to obtain a voice_id after creation/retrieval attempts"}), 500
        # ----- FIN BLOQUE ELIMINADO -----

        tts_url = ELEVEN_TTS_URL_TEMPLATE.format(voice_id=voice_id_to_use) # Usar voice_id_to_use

        # stability and similarity_boost are now stability_val, similarity_boost_val (floats)
        json_payload = {
            "text": generated_text,
            "voice_settings": {
                "stability": stability_val, # Use the float converted values
                "similarity_boost": similarity_boost_val # Use the float converted values
            }
        }

        print(f"Generando TTS con voice_id: {voice_id_to_use}, texto: '{generated_text}', settings: {json_payload['voice_settings']}")
        tts_resp = requests.post(tts_url, headers={**headers, 'Content-Type': 'application/json'}, json=json_payload)

        try:
            tts_resp.raise_for_status()
        except requests.HTTPError as e:
            error_msg = f"Error al generar voz: {tts_resp.text}"
            print(f"ERROR: {error_msg}")
            return jsonify({"error": error_msg}), tts_resp.status_code

        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as out:
            out.write(tts_resp.content)
            out_path = out.name

        return send_file(out_path, mimetype='audio/mpeg', as_attachment=True, download_name='output.mp3')

    except Exception as e:
        print(f"Error general: {e}")
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

    # Define default settings for a new user
    default_settings = {
        "language": "en",  # Default language
        "voice_similarity": 0.85,
        "stability": 0.7,
        "add_background_sound": True,
        "background_volume": 0.5
    }

    try:
        user_id = users_collection.insert_one({
            "username": username,
            "email": email,
            "password": hashed_password,
            "created_at": datetime.utcnow(),
            "settings": default_settings  # Add default settings here
        }).inserted_id

        # Mark activation code as used
        activation_codes_collection.update_one(
            {"_id": activation_code["_id"]},
            {
                "$set": {
                    "used": True,
                    "used_by": user_id,
                    "used_at": datetime.utcnow()
                }
            }
        )
        return jsonify({"message": "User registered successfully", "user_id": str(user_id)}), 201

    except Exception as e:
        print(f"Error during registration: {e}")
        traceback.print_exc()
        return jsonify({"error": "An internal error occurred during registration."}), 500


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
        # Password matches, generate JWT
        token_payload = {
            'user_id': str(user['_id']),
            'username': user['username'],
            'exp': datetime.utcnow() + timedelta(hours=24)  # Token expires in 24 hours
        }
        try:
            token = jwt.encode(token_payload, app.config['JWT_SECRET_KEY'], algorithm='HS256')
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
    # Handle overwrite flag: bypass existing clone return and delete old clone if present
    overwrite = request.values.get('overwrite', 'false').strip().lower() in ('true', '1')
    existing_id = g.current_user.get('voice_clone_id')
    if existing_id:
        if not overwrite:
            return jsonify({"voice_clone_id": existing_id}), 200
        # Overwrite: delete old voice clone from ElevenLabs
        delete_url = f"https://api.elevenlabs.io/v1/voices/{existing_id}"
        try:
            del_resp = requests.delete(delete_url, headers=headers)
            del_resp.raise_for_status()
            print(f"Deleted old voice clone {existing_id} for user {g.current_user.get('username')}")
        except Exception as e:
            print(f"Failed to delete old voice clone {existing_id}: {e}")
    if 'audio' not in request.files:
        return jsonify({"error": "Missing 'audio' file"}), 400
    file = request.files['audio']
    with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename)[1]) as temp:
        file.save(temp.name)
        try:
            audio_seg = AudioSegment.from_file(temp.name)
            if len(audio_seg) > 60 * 1000:
                return jsonify({"error": "Audio duration exceeds 1 minute"}), 400
        except Exception:
            return jsonify({"error": "Invalid audio file"}), 400
    files_payload = {"files": (file.filename, open(temp.name, 'rb'), file.mimetype)}
    data_payload = {
        "name": g.current_user['username'],
        "description": f"Voice clone for user {g.current_user['username']}",
        "labels": "{}",
        "language": "es"
    }
    resp = requests.post(ELEVEN_VOICE_ADD_URL, headers=headers, files=files_payload, data=data_payload)
    try:
        resp.raise_for_status()
    except requests.HTTPError:
        return jsonify({"error": f"ElevenLabs error: {resp.text}"}), resp.status_code
    voice_data = resp.json()
    voice_id = voice_data.get('voice_id')
    if not voice_id:
        return jsonify({"error": "No 'voice_id' returned from ElevenLabs"}), 500
    samples = voice_data.get('samples', [])
    sample_url = samples[0].get('url') if samples and isinstance(samples[0], dict) else None
    users_collection.update_one({"_id": g.current_user['_id']}, {"$set": {"voice_clone_id": voice_id}})
    result = {"voice_clone_id": voice_id}
    if sample_url:
        result['sample_url'] = sample_url
    return jsonify(result), 200

# Add endpoint to fetch current user info
@app.route('/me', methods=['GET'])
@token_required
def me():
    user_data = g.current_user
    # Ensure settings are returned, providing defaults if not present
    default_settings = {
        "language": "en",
        "voice_similarity": 0.85,
        "stability": 0.7,
        "add_background_sound": True,
        "background_volume": 0.5
    }
    settings = user_data.get("settings", default_settings)

    return jsonify({
        "user_id": str(user_data["_id"]),
        "username": user_data["username"],
        "email": user_data["email"],
        "voice_clone_id": user_data.get("voice_clone_id"), # May not exist
        "settings": settings # Add settings to the response
    }), 200

@app.route('/update-settings', methods=['POST'])
@token_required
def update_settings():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400

    current_user_id = g.current_user["_id"]
    
    # Define allowed settings keys and their expected types/validation
    # This helps in sanitizing input
    allowed_settings = {
        "language": str,
        "voice_similarity": float,
        "stability": float,
        "add_background_sound": bool,
        "background_volume": float
    }
    
    new_settings = {}
    for key, value_type in allowed_settings.items():
        if key in data:
            value = data[key]
            # Basic type checking
            if not isinstance(value, value_type):
                return jsonify({"error": f"Invalid type for '{key}'. Expected {value_type.__name__}."}), 400
            
            # Specific range checks (optional, but good practice)
            if key == "voice_similarity" and not (0.0 <= value <= 1.0):
                return jsonify({"error": f"'{key}' must be between 0.0 and 1.0."}), 400
            if key == "stability" and not (0.0 <= value <= 1.0):
                return jsonify({"error": f"'{key}' must be between 0.0 and 1.0."}), 400
            if key == "background_volume" and not (0.0 <= value <= 1.0):
                return jsonify({"error": f"'{key}' must be between 0.0 and 1.0."}), 400
            if key == "language" and value not in ["en", "es", "fr", "de", "it", "pt", "hi", "ja", "ko", "zh-CN"]: # Example list
                 # Consider making this list more dynamic or comprehensive
                print(f"Warning: Language '{value}' not in predefined list. Saving anyway.")
                # return jsonify({"error": f"Unsupported language code '{value}'."}), 400


            new_settings[key] = value

    if not new_settings:
        return jsonify({"error": "No valid settings provided to update."}), 400

    try:
        # Fetch current settings to merge, or use an empty dict if none exist
        user_doc = users_collection.find_one({"_id": current_user_id})
        current_settings = user_doc.get("settings", {})
        
        # Update current settings with new values
        current_settings.update(new_settings)

        result = users_collection.update_one(
            {"_id": current_user_id},
            {"$set": {"settings": current_settings}}
        )

        if result.matched_count == 0:
            return jsonify({"error": "User not found."}), 404
        
        return jsonify({"message": "Settings updated successfully.", "settings": current_settings}), 200

    except Exception as e:
        print(f"Error updating settings: {e}")
        traceback.print_exc()
        return jsonify({"error": "An internal error occurred while updating settings."}), 500

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
