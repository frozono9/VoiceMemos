import requests
import json

# URL del endpoint en tu servidor Flask
FLASK_SERVER_URL = "http://127.0.0.1:5002/generate-audio" # Asegúrate que el puerto es el correcto

def send_audio_request(topic, value, stability=0.7, similarity_boost=0.85):
    """
    Simula una aplicación Swift enviando una solicitud JSON al servidor Flask
    para generar audio.
    """
    payload = {
        "topic": topic,
        "value": value,
        "stability": stability,
        "similarity_boost": similarity_boost
    }
    
    headers = {
        "Content-Type": "application/json"
    }
    
    print(f"Enviando solicitud a {FLASK_SERVER_URL} con payload: {json.dumps(payload)}")
    
    try:
        response = requests.post(FLASK_SERVER_URL, json=payload, headers=headers)
        
        print(f"Respuesta del servidor (Status Code: {response.status_code})")
        
        if response.status_code == 200 and response.headers.get('Content-Type') == 'audio/mpeg':
            # Guardar el archivo MP3 recibido
            with open("generated_audio_from_swift_sim.mp3", "wb") as f:
                f.write(response.content)
            print("Audio MP3 guardado como 'generated_audio_from_swift_sim.mp3'")
            return True, "Audio generado y guardado."
        elif response.status_code == 200: # No es audio/mpeg pero es 200 OK
            print(f"Respuesta inesperada (pero exitosa) del servidor: {response.text}")
            return False, f"Respuesta inesperada del servidor (pero exitosa): {response.text}"
        else:
            # Intentar decodificar el error JSON si es posible
            try:
                error_json = response.json()
                error_message = error_json.get("error", "Error desconocido del servidor.")
                print(f"Error del servidor: {error_message}")
                return False, f"Error del servidor: {error_message}"
            except json.JSONDecodeError:
                print(f"Error del servidor (no JSON): {response.text}")
                return False, f"Error del servidor (no JSON): {response.text}"
                
    except requests.exceptions.RequestException as e:
        print(f"Error de conexión al enviar la solicitud: {e}")
        return False, f"Error de conexión: {str(e)}"

if __name__ == "__main__":
    print("--- Iniciando simulación de cliente Swift ---")
    
    # Caso 1: Solicitud válida
    print("\n--- Caso 1: Solicitud válida ---")
    topic_input = "amistad"
    value_input = "un viejo amigo que no veo hace tiempo"
    print(f"Intentando generar audio para Topic: '{topic_input}', Value: '{value_input}'")
    success, message = send_audio_request(topic_input, value_input)
    print(f"Resultado: {'Éxito' if success else 'Fallo'} - {message}")

    # Caso 2: Solicitud válida con parámetros de voz personalizados
    print("\n--- Caso 2: Solicitud válida con parámetros de voz personalizados ---")
    topic_input_2 = "trabajo"
    value_input_2 = "una nueva oportunidad emocionante"
    stability_input_2 = 0.6
    similarity_input_2 = 0.9
    print(f"Intentando generar audio para Topic: '{topic_input_2}', Value: '{value_input_2}', Stability: {stability_input_2}, Similarity: {similarity_input_2}")
    success, message = send_audio_request(topic_input_2, value_input_2, stability=stability_input_2, similarity_boost=similarity_input_2)
    print(f"Resultado: {'Éxito' if success else 'Fallo'} - {message}")

    # Caso 3: Topic vacío
    print("\n--- Caso 3: Topic vacío ---")
    topic_input_3 = ""
    value_input_3 = "algo sin importancia"
    print(f"Intentando generar audio para Topic: '{topic_input_3}', Value: '{value_input_3}'")
    success, message = send_audio_request(topic_input_3, value_input_3)
    print(f"Resultado: {'Éxito' if success else 'Fallo'} - {message}")

    # Caso 4: Value solo espacios
    print("\n--- Caso 4: Value solo espacios ---")
    topic_input_4 = "espacio"
    value_input_4 = "   "
    print(f"Intentando generar audio para Topic: '{topic_input_4}', Value: '{value_input_4}'")
    success, message = send_audio_request(topic_input_4, value_input_4)
    print(f"Resultado: {'Éxito' if success else 'Fallo'} - {message}")

    # Caso 5: Stability inválido (string no numérico)
    print("\n--- Caso 5: Stability inválido ---")
    topic_input_5 = "prueba"
    value_input_5 = "estabilidad incorrecta"
    print(f"Intentando generar audio para Topic: '{topic_input_5}', Value: '{value_input_5}', Stability: 'muy alto'")
    success, message = send_audio_request(topic_input_5, value_input_5)
    print(f"Resultado: {'Éxito' if success else 'Fallo'} - {message}")
    
    print("\n--- Simulación de cliente Swift finalizada ---")
