# Turing Test Arena

Interfaz web simple para ejecutar una prueba de Turing con dos chats paralelos:

- `Chat A`: una conversacion con un humano real que responde desde un panel privado.
- `Chat B`: una conversacion contra tu deployment de Azure OpenAI.

La pagina esta pensada para que un companero compare ambos chats y luego marque cual cree que corresponde a una persona real.

## Archivos principales

- `server.ps1`: servidor HTTP ligero en PowerShell.
- `public/index.html`: estructura de la interfaz.
- `public/styles.css`: estilos responsive.
- `public/app.js`: logica de la vista del participante.
- `public/operator.html`: panel privado para el operador humano.
- `public/operator.js`: logica del chat humano.
- `.env.example`: variables de entorno necesarias.

## Como configurarlo

1. Duplica `.env.example` como `.env`.
2. Llena tus credenciales de Azure:
   - `AZURE_OPENAI_API_KEY`
   - `AZURE_OPENAI_ENDPOINT`
   - `AZURE_OPENAI_DEPLOYMENT`
   - `AZURE_OPENAI_API_VERSION`
3. Ajusta `AZURE_SYSTEM_PROMPT` si quieres cambiar el estilo del modelo.

## Como ejecutarlo

Desde PowerShell, en la carpeta del proyecto:

```powershell
powershell -ExecutionPolicy Bypass -File .\server.ps1
```

Despues abre [http://localhost:8080](http://localhost:8080).

Para responder como humano, abre tambien [http://localhost:8080/operator.html](http://localhost:8080/operator.html).

## Flujo de uso

1. El participante escribe mensajes en ambos chats desde la pagina principal.
2. Tus respuestas humanas se envian desde `operator.html`.
3. El chat humano se sincroniza automaticamente en ambas vistas.
4. Al final, el participante usa el selector superior para guardar su conclusion localmente en el navegador.

## Notas

- El servidor no usa dependencias externas.
- El canal humano se guarda solo en memoria; si reinicias el servidor, la conversacion se borra.
- `Chat B` usa el endpoint de Azure OpenAI para `chat/completions`.
- Si quieres ocultar aun mas cual es cual, puedes cambiar las etiquetas visuales del frontend en `public/index.html`.
