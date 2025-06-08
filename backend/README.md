# 🎤 AI Voice Cloning App

Una aplicación nativa de macOS que permite clonar tu voz usando la API de ElevenLabs y generar audios con texto personalizado.

## ✨ Características

- **Grabación directa**: Graba tu voz directamente desde la aplicación
- **Carga de archivos MP3**: Sube archivos MP3 desde tu ordenador para entrenar la IA
- **Interfaz nativa**: App nativa de macOS con interfaz web integrada
- **Ajustes avanzados**: Controla la similitud y estabilidad de la voz clonada
- **Sonido de fondo**: Opción para añadir sonido de fondo (fan.mp3)
- **Generación rápida**: Clona tu voz y genera audios en segundos

## 🚀 Instalación y Uso

### Prerequisitos
- macOS (versión reciente)
- Xcode instalado
- Python 3 instalado
- Clave API de ElevenLabs
- Clave API de Google (para Gemini)

### Configuración

1. **Configurar las API Keys**:
   - Crea un archivo `.env` basado en el ejemplo `.env.example`
   - Configura ambas claves de API:
     ```
     # Clave de ElevenLabs para la clonación de voz
     ELEVEN_LABS_API_KEY=tu_clave_elevenlabs_aqui
     
     # Clave de Google API para Gemini (generación de pensamientos)
     GOOGLE_API_KEY=tu_clave_google_aqui
     ```
   - Obtén tu clave de API de Gemini en: [Google AI Studio](https://ai.google.dev)

2. **Ejecutar la aplicación**:
   ```bash
   cd /Users/nicolasrosales/Desktop/prebaalex
   ./start_app.sh
   ```

3. **En Xcode**:
   - Selecciona "My Mac" como destino
   - Presiona el botón Play (▶) para compilar y ejecutar
   - La aplicación se abrirá como una app nativa de macOS

## 📱 Cómo usar la aplicación

### Paso 1: Entrenar tu voz
Tienes dos opciones:

**Opción A - Grabar directamente:**
1. Haz clic en "🎙️ Grabar Voz"
2. Habla por al menos 30 segundos (recomendado: 2 minutos)
3. Haz clic en "⏹️ Parar" cuando termines

**Opción B - Subir archivo MP3:**
1. Haz clic en "Subir archivo MP3"
2. Selecciona un archivo MP3 de tu ordenador
3. Recomendado: 2 minutos de audio claro y sin ruido

### Paso 2: Configurar ajustes (opcional)
- **Similitud de voz**: Aumenta para un sonido más parecido a tu voz
- **Estabilidad**: Aumenta para un habla más consistente
- **Sonido de fondo**: Activa para añadir el audio de fan.mp3

### Paso 3: Generar audio
1. Escribe el texto que quieres que diga tu voz clonada
2. Haz clic en "🚀 Generar Audio con IA"
3. Espera unos segundos mientras la IA procesa
4. Descarga o reproduce el audio generado

## 🔧 Solución de problemas

### "No se pudo conectar al servidor"
- Asegúrate de que el servidor Flask esté ejecutándose
- Verifica que no haya otro proceso usando el puerto 5001
- Ejecuta manualmente: `python3 main.py`

### "API Key inválida"
- Verifica que tu clave API de ElevenLabs sea correcta en `.env`
- Asegúrate de que tu cuenta de ElevenLabs tenga créditos disponibles

### Problemas de compilación en Xcode
- Asegúrate de tener Xcode actualizado
- Limpia el proyecto: Product → Clean Build Folder
- Reinicia Xcode si es necesario

## 📁 Estructura del proyecto

```
prebaalex/
├── main.py                 # Servidor Flask backend
├── requirements.txt        # Dependencias de Python
├── start_app.sh           # Script para iniciar todo
├── fan.mp3                # Audio de fondo opcional
├── templates/
│   └── index.html         # Interfaz web
└── Pruebalatuare/         # Proyecto Xcode
    ├── Pruebalatuare/
    │   ├── ContentView.swift    # Vista principal
    │   ├── WebView.swift        # Componente web
    │   └── PruebalatuareApp.swift # App principal
    └── Pruebalatuare.xcodeproj
```

## 🎯 Tips para mejores resultados

1. **Calidad del audio**: Usa audio claro, sin ruido de fondo
2. **Duración**: 2 minutos de audio dan mejores resultados que 30 segundos
3. **Hablado natural**: Habla de forma natural, no forzada
4. **Ajustes**: Experimenta con los controles de similitud y estabilidad
5. **Textos cortos**: Comienza con textos cortos para probar la calidad

## 🆘 Soporte

Si tienes problemas:
1. Revisa que tu clave API de ElevenLabs sea válida
2. Verifica que tengas créditos en tu cuenta de ElevenLabs
3. Asegúrate de que el servidor Flask esté ejecutándose
4. Prueba con un archivo MP3 diferente

¡Disfruta clonando tu voz con IA! 🎉
