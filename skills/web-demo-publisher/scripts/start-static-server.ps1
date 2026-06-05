param(
    [Parameter(Mandatory = $true)][string]$Root,
    [int]$Port = 9999
)

Set-StrictMode -Version Latest

$resolvedRoot = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()

function Get-MimeType {
    param([string]$Path)
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".svg" { return "image/svg+xml" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".webp" { return "image/webp" }
        ".ico" { return "image/x-icon" }
        default { return "application/octet-stream" }
    }
}

function Test-ChildPath {
    param([string]$Parent, [string]$Child)
    return $Child.Equals($Parent, [System.StringComparison]::OrdinalIgnoreCase) -or
        $Child.StartsWith($Parent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $Child.StartsWith($Parent + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Write-Response {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode,
        [string]$StatusText,
        [byte[]]$Body,
        [string]$ContentType = "text/plain; charset=utf-8"
    )

    $header = "HTTP/1.1 $StatusCode $StatusText`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
}

while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
        $stream = $client.GetStream()
        $buffer = New-Object byte[] 8192
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) { continue }

        $request = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
        $firstLine = ($request -split "`r?`n", 2)[0]
        $parts = $firstLine -split "\s+"
        $rawPath = if ($parts.Count -ge 2) { $parts[1] } else { "/" }
        $urlPath = ($rawPath -split "\?", 2)[0]
        $requestPath = [System.Uri]::UnescapeDataString($urlPath.TrimStart('/')).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        if ([string]::IsNullOrWhiteSpace($requestPath)) { $requestPath = "index.html" }

        $candidate = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $requestPath))
        if (-not (Test-ChildPath -Parent $resolvedRoot -Child $candidate)) {
            Write-Response -Stream $stream -StatusCode 403 -StatusText "Forbidden" -Body ([System.Text.Encoding]::UTF8.GetBytes("Forbidden"))
            continue
        }
        if (Test-Path -LiteralPath $candidate -PathType Container) { $candidate = Join-Path $candidate "index.html" }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $fallback = Join-Path $resolvedRoot "index.html"
            if (Test-Path -LiteralPath $fallback -PathType Leaf) { $candidate = $fallback }
            else {
                Write-Response -Stream $stream -StatusCode 404 -StatusText "Not Found" -Body ([System.Text.Encoding]::UTF8.GetBytes("Not Found"))
                continue
            }
        }

        $bytes = [System.IO.File]::ReadAllBytes($candidate)
        Write-Response -Stream $stream -StatusCode 200 -StatusText "OK" -Body $bytes -ContentType (Get-MimeType -Path $candidate)
    }
    catch {
        try { Write-Response -Stream $stream -StatusCode 500 -StatusText "Internal Server Error" -Body ([System.Text.Encoding]::UTF8.GetBytes("Internal Server Error")) } catch { }
    }
    finally {
        if ($null -ne $client) { $client.Close() }
    }
}

