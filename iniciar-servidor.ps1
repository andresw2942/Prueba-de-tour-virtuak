$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PSScriptRoot)
$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
$listener = New-Object System.Net.HttpListener
$port = $null

foreach ($candidate in 8765..8775) {
  try {
    $listener.Prefixes.Clear()
    $listener.Prefixes.Add("http://127.0.0.1:$candidate/")
    $listener.Start()
    $port = $candidate
    break
  } catch {
    if ($listener.IsListening) { $listener.Stop() }
  }
}

if ($null -eq $port) {
  Write-Host 'No se pudo iniciar el servidor local. Cierra otras vistas previas e inténtalo otra vez.' -ForegroundColor Red
  Read-Host 'Pulsa Enter para cerrar'
  exit 1
}

$mimeTypes = @{
  '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'
  '.webp' = 'image/webp'; '.wav' = 'audio/wav'; '.svg' = 'image/svg+xml'; '.map' = 'application/json; charset=utf-8'
}

Start-Process "http://127.0.0.1:$port/index.html"
Write-Host "Recorrido disponible en http://127.0.0.1:$port/index.html" -ForegroundColor Green
Write-Host 'Mantén esta ventana abierta mientras exploras el recorrido. Pulsa Ctrl+C para detenerlo.'

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    try {
      $relative = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
      if ([String]::IsNullOrWhiteSpace($relative)) { $relative = 'index.html' }
      if ($relative -match '(^|[\/])\.\.([\/]|$)') {
        $context.Response.StatusCode = 403
        $context.Response.Close()
        continue
      }
      $target = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
      if (-not $target.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($target)) {
        $context.Response.StatusCode = 404
        $context.Response.Close()
        continue
      }
      $extension = [IO.Path]::GetExtension($target).ToLowerInvariant()
      $context.Response.ContentType = if ($mimeTypes.ContainsKey($extension)) { $mimeTypes[$extension] } else { 'application/octet-stream' }
      $bytes = [IO.File]::ReadAllBytes($target)
      $context.Response.ContentLength64 = $bytes.Length
      $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      $context.Response.Close()
    } catch {
      $context.Response.StatusCode = 500
      $context.Response.Close()
    }
  }
} finally {
  if ($listener.IsListening) { $listener.Stop() }
  $listener.Close()
}
