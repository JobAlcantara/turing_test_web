$ErrorActionPreference = "Stop"

$script:HumanChatMessages = New-Object System.Collections.ArrayList
$script:NextHumanMessageId = 1

function Load-EnvFile {
    param(
        [string]$Path = ".env"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()

        if (-not $line -or $line.StartsWith("#")) {
            return
        }

        $separatorIndex = $line.IndexOf("=")
        if ($separatorIndex -lt 1) {
            return
        }

        $name = $line.Substring(0, $separatorIndex).Trim()
        $value = $line.Substring($separatorIndex + 1).Trim()

        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

function Get-ContentType {
    param(
        [string]$Path
    )

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".svg" { return "image/svg+xml" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        default { return "application/octet-stream" }
    }
}

function Build-ResponseBytes {
    param(
        [int]$StatusCode,
        [string]$ReasonPhrase,
        [string]$ContentType,
        [byte[]]$BodyBytes
    )

    $headers = @(
        "HTTP/1.1 $StatusCode $ReasonPhrase",
        "Content-Type: $ContentType",
        "Content-Length: $($BodyBytes.Length)",
        "Connection: close",
        ""
    ) -join "`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes("$headers`r`n")
    $buffer = New-Object byte[] ($headerBytes.Length + $BodyBytes.Length)
    [System.Array]::Copy($headerBytes, 0, $buffer, 0, $headerBytes.Length)
    [System.Array]::Copy($BodyBytes, 0, $buffer, $headerBytes.Length, $BodyBytes.Length)
    return $buffer
}

function Build-JsonResponseBytes {
    param(
        [int]$StatusCode,
        [string]$ReasonPhrase,
        [object]$Payload
    )

    $json = $Payload | ConvertTo-Json -Depth 20
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return Build-ResponseBytes -StatusCode $StatusCode -ReasonPhrase $ReasonPhrase -ContentType "application/json; charset=utf-8" -BodyBytes $bodyBytes
}

function Read-HttpRequest {
    param(
        [System.Net.Sockets.NetworkStream]$Stream
    )

    $buffer = New-Object byte[] 1024
    $requestBytes = New-Object System.Collections.Generic.List[byte]
    $headerTerminator = [System.Text.Encoding]::ASCII.GetBytes("`r`n`r`n")
    $headerEndIndex = -1

    while ($headerEndIndex -lt 0) {
        $bytesRead = $Stream.Read($buffer, 0, $buffer.Length)
        if ($bytesRead -le 0) {
            break
        }

        for ($i = 0; $i -lt $bytesRead; $i++) {
            $requestBytes.Add($buffer[$i])
        }

        $currentArray = $requestBytes.ToArray()
        for ($i = 0; $i -le $currentArray.Length - $headerTerminator.Length; $i++) {
            $matches = $true
            for ($j = 0; $j -lt $headerTerminator.Length; $j++) {
                if ($currentArray[$i + $j] -ne $headerTerminator[$j]) {
                    $matches = $false
                    break
                }
            }

            if ($matches) {
                $headerEndIndex = $i + $headerTerminator.Length
                break
            }
        }
    }

    if ($headerEndIndex -lt 0) {
        throw "No se pudo leer la cabecera HTTP."
    }

    $allBytes = $requestBytes.ToArray()
    $headerText = [System.Text.Encoding]::ASCII.GetString($allBytes, 0, $headerEndIndex)
    $headerLines = $headerText.Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries)

    if ($headerLines.Length -eq 0) {
        throw "La solicitud HTTP esta vacia."
    }

    $requestLineParts = $headerLines[0].Split(" ")
    if ($requestLineParts.Length -lt 2) {
        throw "Linea de solicitud HTTP invalida."
    }

    $headers = @{}
    foreach ($line in $headerLines[1..($headerLines.Length - 1)]) {
        $separatorIndex = $line.IndexOf(":")
        if ($separatorIndex -lt 1) {
            continue
        }

        $name = $line.Substring(0, $separatorIndex).Trim().ToLowerInvariant()
        $value = $line.Substring($separatorIndex + 1).Trim()
        $headers[$name] = $value
    }

    $contentLength = 0
    if ($headers.ContainsKey("content-length")) {
        $contentLength = [int]$headers["content-length"]
    }

    $bodyBytes = New-Object byte[] $contentLength
    $bodyBytesAlreadyRead = $allBytes.Length - $headerEndIndex

    if ($bodyBytesAlreadyRead -gt 0) {
        [System.Array]::Copy($allBytes, $headerEndIndex, $bodyBytes, 0, [Math]::Min($bodyBytesAlreadyRead, $contentLength))
    }

    $offset = [Math]::Min($bodyBytesAlreadyRead, $contentLength)
    while ($offset -lt $contentLength) {
        $bytesRead = $Stream.Read($bodyBytes, $offset, $contentLength - $offset)
        if ($bytesRead -le 0) {
            break
        }

        $offset += $bytesRead
    }

    $bodyText = if ($contentLength -gt 0) { [System.Text.Encoding]::UTF8.GetString($bodyBytes, 0, $contentLength) } else { "" }

    return @{
        Method = $requestLineParts[0].ToUpperInvariant()
        Path = $requestLineParts[1]
        Headers = $headers
        Body = $bodyText
    }
}

function Get-NormalizedPath {
    param(
        [string]$RawPath
    )

    if ($RawPath -match "^https?://") {
        return ([System.Uri]$RawPath).PathAndQuery
    }

    return $RawPath
}

function Add-HumanMessage {
    param(
        [ValidateSet("participant", "operator")][string]$Sender,
        [string]$Content
    )

    $entry = [PSCustomObject]@{
        id = $script:NextHumanMessageId
        sender = $Sender
        content = $Content
        createdAt = (Get-Date).ToString("o")
    }

    $script:NextHumanMessageId += 1
    [void]$script:HumanChatMessages.Add($entry)
}

function Get-HumanMessages {
    return @($script:HumanChatMessages)
}

function Invoke-AzureChat {
    param(
        [object[]]$Messages
    )

    $apiKey = $env:AZURE_OPENAI_API_KEY
    $endpoint = $env:AZURE_OPENAI_ENDPOINT
    $deployment = $env:AZURE_OPENAI_DEPLOYMENT
    $apiVersion = $env:AZURE_OPENAI_API_VERSION
    $systemPrompt = $env:AZURE_SYSTEM_PROMPT

    if (-not $apiKey -or -not $endpoint -or -not $deployment -or -not $apiVersion) {
        throw "Faltan variables AZURE_OPENAI_API_KEY, AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_DEPLOYMENT o AZURE_OPENAI_API_VERSION en el archivo .env."
    }

    $messageList = New-Object System.Collections.Generic.List[object]

    if ($systemPrompt) {
        $messageList.Add(@{
            role = "system"
            content = $systemPrompt
        })
    }

    foreach ($message in $Messages) {
        if ($message.role -and $message.content) {
            $messageList.Add(@{
                role = [string]$message.role
                content = [string]$message.content
            })
        }
    }

    $uri = "{0}/openai/deployments/{1}/chat/completions?api-version={2}" -f $endpoint.TrimEnd("/"), $deployment, $apiVersion
    $payload = @{
        messages = @($messageList.ToArray())
        temperature = 0.8
    }

    $headers = @{
        "api-key" = $apiKey
    }

    $apiResponse = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body ($payload | ConvertTo-Json -Depth 20)
    return $apiResponse.choices[0].message.content
}

function Handle-AzureRoute {
    param(
        [string]$Body
    )

    try {
        $payload = $Body | ConvertFrom-Json
        $messages = @($payload.messages)

        if (-not $messages -or $messages.Count -eq 0) {
            throw "No se recibieron mensajes para enviar al modelo."
        }

        $reply = Invoke-AzureChat -Messages $messages
        return Build-JsonResponseBytes -StatusCode 200 -ReasonPhrase "OK" -Payload @{ reply = $reply }
    }
    catch {
        return Build-JsonResponseBytes -StatusCode 500 -ReasonPhrase "Internal Server Error" -Payload @{ error = $_.Exception.Message }
    }
}

function Handle-HumanSendRoute {
    param(
        [string]$Body
    )

    try {
        $payload = $Body | ConvertFrom-Json
        $sender = [string]$payload.sender
        $content = [string]$payload.content

        if (-not $sender -or -not $content) {
            throw "Debes enviar sender y content."
        }

        Add-HumanMessage -Sender $sender -Content $content
        return Build-JsonResponseBytes -StatusCode 200 -ReasonPhrase "OK" -Payload @{
            ok = $true
            messages = @(Get-HumanMessages)
        }
    }
    catch {
        return Build-JsonResponseBytes -StatusCode 400 -ReasonPhrase "Bad Request" -Payload @{ error = $_.Exception.Message }
    }
}

function Handle-HumanMessagesRoute {
    return Build-JsonResponseBytes -StatusCode 200 -ReasonPhrase "OK" -Payload @{
        messages = @(Get-HumanMessages)
    }
}

function Handle-StaticRoute {
    param(
        [string]$RawPath,
        [string]$PublicRoot
    )

    $relativePath = [System.Uri]::UnescapeDataString(($RawPath.Split("?")[0]).TrimStart("/"))
    if (-not $relativePath) {
        $relativePath = "index.html"
    }

    $candidate = [System.IO.Path]::GetFullPath((Join-Path $PublicRoot ($relativePath -replace "/", "\")))
    if (-not $candidate.StartsWith($PublicRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return Build-JsonResponseBytes -StatusCode 403 -ReasonPhrase "Forbidden" -Payload @{ error = "Ruta no permitida." }
    }

    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        return Build-JsonResponseBytes -StatusCode 404 -ReasonPhrase "Not Found" -Payload @{ error = "Archivo no encontrado." }
    }

    $bodyBytes = [System.IO.File]::ReadAllBytes($candidate)
    return Build-ResponseBytes -StatusCode 200 -ReasonPhrase "OK" -ContentType (Get-ContentType -Path $candidate) -BodyBytes $bodyBytes
}

function Handle-Request {
    param(
        [hashtable]$Request,
        [string]$PublicRoot
    )

    $normalizedPath = Get-NormalizedPath -RawPath $Request.Path
    if ($Request.Method -eq "POST" -and $normalizedPath.StartsWith("/api/chat/azure")) {
        return Handle-AzureRoute -Body $Request.Body
    }

    if ($Request.Method -eq "POST" -and $normalizedPath.StartsWith("/api/chat/human/send")) {
        return Handle-HumanSendRoute -Body $Request.Body
    }

    if ($Request.Method -eq "GET" -and $normalizedPath.StartsWith("/api/chat/human/messages")) {
        return Handle-HumanMessagesRoute
    }

    if ($Request.Method -eq "GET") {
        return Handle-StaticRoute -RawPath $normalizedPath -PublicRoot $PublicRoot
    }

    return Build-JsonResponseBytes -StatusCode 405 -ReasonPhrase "Method Not Allowed" -Payload @{ error = "Metodo no soportado." }
}

Load-EnvFile

$port = if ($env:PORT) { [int]$env:PORT } else { 8080 }
$publicRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "public"))

if (-not (Test-Path -LiteralPath $publicRoot -PathType Container)) {
    throw "No existe la carpeta public."
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
$listener.Start()

Write-Host "Servidor listo en http://localhost:$port"
Write-Host "Participante: http://localhost:$port/"
Write-Host "Operador humano: http://localhost:$port/operator.html"
Write-Host "Presiona Ctrl+C para detenerlo."

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $request = Read-HttpRequest -Stream $stream
            $responseBytes = Handle-Request -Request $request -PublicRoot $publicRoot
            $stream.Write($responseBytes, 0, $responseBytes.Length)
            $stream.Flush()
        }
        catch {
            $fallback = Build-JsonResponseBytes -StatusCode 500 -ReasonPhrase "Internal Server Error" -Payload @{ error = $_.Exception.Message }
            if ($stream) {
                $stream.Write($fallback, 0, $fallback.Length)
                $stream.Flush()
            }
        }
        finally {
            if ($stream) {
                $stream.Dispose()
            }

            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}
