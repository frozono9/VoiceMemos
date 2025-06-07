import os
import tempfile
import requests
import json
import traceback
from flask import Flask, request, send_file, jsonify, render_template
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
            
            # You might want to fetch the user from DB and pass it or store in flask.g
            # from flask import g
            # current_user = users_collection.find_one({"_id": ObjectId(data["user_id"])})
            # if not current_user:
            #     return jsonify({"message": "User not found for token"}), 401
            # g.current_user = current_user

        except jwt.ExpiredSignatureError:
            return jsonify({"message": "Token has expired!"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"message": "Token is invalid!"}), 401
        except Exception as e:
            print(f"Token validation error: {e}")
            traceback.print_exc() # It's good to log the full traceback for unexpected errors
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
        voice_id_to_use = ALEX_LATORRE_VOICE_ID
        if not voice_id_to_use:
            # Intenta obtener el ID de nuevo si no se encontró al inicio
            voice_id_to_use = get_alex_latorre_voice_id()
            if not voice_id_to_use:
                return jsonify({"error": "Voice 'Alex Latorre' not found or could not be retrieved. Please check backend logs."}), 500

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

    try:
        user_id = users_collection.insert_one({
            "username": username,
            "email": email,
            "password": hashed_password,
            "created_at": datetime.utcnow()
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
        # For now, just returning success. JWT generation would go here.
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


# Configuración adicional para CORS
@app.route('/generate-thought', methods=['GET'])
def generate_thought():
    """Endpoint for generating a thought based on topic and value"""
    topic = request.args.get('topic')
    value = request.args.get('value')
    
    if not topic or not value:
        return jsonify({"error": "Both topic and value are required"}), 400
    
    # Check for inappropriate content
    if _is_likely_inappropriate(topic) or _is_likely_inappropriate(value):
        generated_text = "This morning I woke up thinking about how interesting magic is and how it can surprise people."
        print(f"Warning: Potentially inappropriate content detected. Using safe fallback.")
    else:
        safe_prompt = f"""
You are generating a short, first-person sentence that sounds like a fleeting thought I had this morning.

This thought should feel like a subtle intuition, prediction, or premonition I had after waking up — something that might come true later today, like a magic trick.

IMPORTANT:
- You MUST explicitly mention BOTH the topic ('{topic}') and the value ('{value}').
- Your response must sound natural, as if I casually thought this to myself while getting ready for the day.
- The sentence should be short (one sentence or two at most), positive or neutral in tone, and suitable for all audiences.
- It should feel like a magical prediction or hunch about someone I might meet or something I might notice during the day.

Examples:

If topic is 'academic' and value is 'I got an A+ in math':
✅ "I had this weird feeling this morning that someone I meet today will be proud of getting an A+ in math."

If topic is 'travel' and value is 'Paris':
✅ "As I woke up today, I had this odd thought that someone around me will mention travel plans to Paris."

If topic is 'fears' and value is 'spiders':
✅ "Okay, so… I just woke up, and I had this weird dream that I feel like I should record. In the dream, I met someone… and they told me they had this insane fear of spiders. Like, full-on panic. I know, it’s random… but it felt kinda specific, so… yeah."

Your response must:
- Be in English.
- Be phrased as a personal morning thought or hunch.
- Clearly include both the topic ('{topic}') and the value ('{value}').

Only return the sentence, nothing else.
"""
        generated_text = _generate_thought_text(safe_prompt, topic, value)
    
    print(f"Generated thought: {generated_text}")
    return jsonify({"thought": generated_text})

@app.after_request
def after_request(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response

if __name__ == '__main__':
    # Puerto 5002 para evitar conflictos
    app.run(host='0.0.0.0', port=5002, debug=True)
