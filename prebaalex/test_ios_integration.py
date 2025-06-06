#!/usr/bin/env python3
"""
Script para probar la integración entre la app iOS y el backend de Python.
Este script simula lo que haría la app de iOS, enviando tópico y valor al 
backend y recibiendo un mp3 generado.
"""

import requests
import json
import os
from datetime import datetime

# URL del endpoint en el servidor Flask
FLASK_SERVER_URL = "http://127.0.0.1:5002/generate-audio"

def test_generate_audio(topic, value, stability=0.7, similarity_boost=0.85):
    """
    Simula una solicitud desde la app iOS al backend de Python para generar audio.
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
    
    print(f"\n🚀 Enviando solicitud al backend con:")
    print(f"    - Topic: {topic}")
    print(f"    - Value: {value}")
    print(f"    - Stability: {stability}")
    print(f"    - Similarity Boost: {similarity_boost}\n")
    
    try:
        # Realizar la solicitud al servidor
        response = requests.post(FLASK_SERVER_URL, json=payload, headers=headers)
        
        # Verificar si la solicitud fue exitosa
        if response.status_code == 200:
            # El servidor ha devuelto el archivo de audio correctamente
            audio_data = response.content
            file_size = len(audio_data) / 1024  # Tamaño en KB
            
            # Guardar el archivo de audio para verificarlo
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_file = f"test_output_{timestamp}.mp3"
            
            with open(output_file, "wb") as f:
                f.write(audio_data)
            
            print(f"✅ Audio generado correctamente!")
            print(f"📊 Tamaño del archivo: {file_size:.2f} KB")
            print(f"💾 Guardado como: {output_file}")
            return True, output_file
        else:
            print(f"❌ Error en la solicitud: Código {response.status_code}")
            try:
                error_info = response.json()
                print(f"Mensaje de error: {error_info.get('error', 'No hay detalles adicionales')}")
            except:
                print(f"Cuerpo de respuesta: {response.text[:500]}...")
            return False, None
            
    except Exception as e:
        print(f"❌ Excepción: {str(e)}")
        return False, None

if __name__ == "__main__":
    # Valores de prueba
    topic = input("Ingrese el tópico (ej: 'miedos personales', 'películas'): ") or "miedos personales"
    value = input("Ingrese el valor (ej: 'arañas', 'Star Wars'): ") or "arañas"
    
    success, output_file = test_generate_audio(topic, value)
    
    if success:
        print("\n🎵 Puedes reproducir el archivo de audio generado con un reproductor de audio.")
        print("👉 Para la integración real en iOS, este contenido se enviaría directamente a la app para reproducción.")
    else:
        print("\n⚠️ No se pudo completar la prueba. Verifica que el servidor esté en ejecución en http://127.0.0.1:5002")
