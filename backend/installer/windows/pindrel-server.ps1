# Starts and stops the Pindrel server on Windows: the bundled PostgreSQL (when server.env says EMBEDDED_POSTGRES=true) and
# pindrel-server.exe. The installer's shortcuts and the portable folder (iniciar.cmd, parar.cmd) all go through it.
#   -Action start  in the background, hidden: starts the database, then the server; a server that dies at once is tried
#                  again a few times, and a message says why if it never comes up. It leaves after ~20 s (a PowerShell left
#                  waiting next to the server would hold ~80 MB: measured with the gateway's script).
#   -Action run    in this window (the portable folder): creates server.env on the first run, stops the database at the end.
#   -Action stop   stops the server and the database.
#   -Action init   creates server.env (portable defaults) when it is missing and prepares the database, then stops it.
# The folder of this script holds pindrel-server.exe, public\ (the web) and pgsql\ (PostgreSQL); -Data holds server.env,
# the database (pgdata\), the uploaded files and the logs.
# Saved as UTF-8 WITH a byte order mark: Windows PowerShell 5.1 reads a file without one as ANSI and garbles the accents.
param(
  [Parameter(Mandatory = $true)][ValidateSet('start', 'run', 'stop', 'init')][string]$Action,
  [Parameter(Mandatory = $true)][string]$Data,
  # no message boxes (the installer and the CI read the exit code and the logs instead)
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$App = $PSScriptRoot
$Exe = Join-Path $App 'pindrel-server.exe'
$PgBin = Join-Path $App 'pgsql\bin'
$Data = [IO.Path]::GetFullPath($Data)
$Conf = Join-Path $Data 'server.env'
$PgData = Join-Path $Data 'pgdata'
$PgLog = Join-Path $Data 'postgres.log'
$Log = Join-Path $Data 'server.log'
$Flag = Join-Path $Data 'stopped.flag'
$SupportUrl = 'https://github.com/JoaoVitor197843/pindrel/issues'

function Say([string]$Text) {
  if ($Quiet -or $Action -eq 'run') { Write-Host $Text; return }
  # the Windows Forms library (tens of MB) is loaded only when there is a message to show
  Add-Type -AssemblyName System.Windows.Forms
  $nl = [Environment]::NewLine
  [void][System.Windows.Forms.MessageBox]::Show($Text + $nl + $nl + "Registros: $Data (server.log, postgres.log)" + $nl +
    "Se o problema continuar, fale com quem mantém o projeto: $SupportUrl", 'Pindrel Server')
}

# The same rules as the server's own reader (backend/internal/config/envfile.go) and the gateway's: KEY=VALUE, # comments,
# `export ` accepted, one pair of matching quotes stripped, nothing expanded, the last line for a key wins.
function Read-Settings([string]$File) {
  $s = @{}
  if (-not (Test-Path -LiteralPath $File)) { return $s }
  foreach ($raw in [IO.File]::ReadAllLines($File)) {
    $line = $raw.Trim().TrimStart([char]0xFEFF)
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    if ($line.StartsWith('export ')) { $line = $line.Substring(7).TrimStart() }
    $i = $line.IndexOf('=')
    if ($i -lt 1) { continue }
    $k = $line.Substring(0, $i).Trim()
    if ($k -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
    $v = $line.Substring($i + 1).Trim()
    if ($v.Length -ge 2 -and ($v[0] -eq '"' -or $v[0] -eq "'") -and $v[$v.Length - 1] -eq $v[0]) { $v = $v.Substring(1, $v.Length - 2) }
    $s[$k] = $v
  }
  return $s
}

# Runs a program and returns its exit code and everything it printed. Windows PowerShell 5.1 turns a line on stderr into
# an error that $ErrorActionPreference = 'Stop' would throw at once, so it is relaxed around the call.
function Invoke-Native([string]$File, [string[]]$Arguments) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $File @Arguments 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $old
  }
  return [pscustomobject]@{ Code = $code; Text = ($out -join [Environment]::NewLine) }
}

# Free = nobody listens on it and Windows did not reserve it (Hyper-V, WSL and Docker reserve ranges). Never opens a
# socket: that would make the Windows Firewall ask about "Windows PowerShell".
function Test-PortFree([int]$Port) {
  if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) { return $false }
  foreach ($l in (netsh interface ipv4 show excludedportrange protocol=tcp)) {
    if ($l -match '^\s*(\d+)\s+(\d+)') {
      if ($Port -ge [int]$Matches[1] -and $Port -le [int]$Matches[2]) { return $false }
    }
  }
  return $true
}

function Find-FreePort([int]$From, [int]$Count) {
  for ($p = $From; $p -lt $From + $Count; $p++) { if (Test-PortFree $p) { return $p } }
  throw "nenhuma porta livre entre $From e $($From + $Count - 1)"
}

function New-Secret {
  $r = Invoke-Native $Exe @('--new-secret')
  if ($r.Code -ne 0 -or $r.Text.Trim().Length -lt 32) { throw "pindrel-server.exe --new-secret falhou: $($r.Text)" }
  return $r.Text.Trim()
}

# The settings of a portable folder: everything relative to the data folder (the server runs inside it), so the folder
# can be moved or copied to a pen drive and keeps working.
function New-PortableSettings {
  if (Test-Path -LiteralPath $Conf) { return }
  New-Item -ItemType Directory -Force -Path $Data | Out-Null
  $lines = @(
    '# Configuração do servidor do Pindrel, criada na primeira vez. Linhas "CHAVE=valor"; # comenta.',
    '# Veja server.env.example na pasta do programa. Depois de editar, pare e inicie o servidor de novo.',
    'SERVER_NAME=Pindrel',
    "PORT=$(Find-FreePort 8080 20)",
    'WEB_DIR=..\public',
    'FILES_DIR=files',
    'FILES_MIN_FREE_BYTES=2147483648',
    'EMBEDDED_POSTGRES=true',
    'DB_HOST=127.0.0.1',
    "DB_PORT=$(Find-FreePort 5433 60)",
    'DB_USER=pindrel',
    "DB_PASSWORD=$(New-Secret)",
    'DB_NAME=pindrel',
    'SSL_MODE=disable',
    "JWT_SECRET=$(New-Secret)",
    'JWT_ACCESS_EXPIRY=15m',
    'JWT_REFRESH_EXPIRY=720h'
  )
  [IO.File]::WriteAllLines($Conf, [string[]]$lines)
}

function Test-Embedded($s) { return ($s['EMBEDDED_POSTGRES'] -eq 'true') }

function Test-DatabaseRunning {
  if (-not (Test-Path -LiteralPath (Join-Path $PgData 'PG_VERSION'))) { return $false }
  return ((Invoke-Native (Join-Path $PgBin 'pg_ctl.exe') @('status', '-D', $PgData)).Code -eq 0)
}

function Start-Database($s) {
  if (Test-DatabaseRunning) { return }
  if (-not (Test-PortFree ([int]$s['DB_PORT']))) {
    throw "a porta $($s['DB_PORT']) do banco de dados está ocupada por outro programa. Troque DB_PORT no server.env."
  }
  # -w waits until it accepts connections; pg_ctl drops the administrator rights PostgreSQL refuses to run with.
  # NOT through Invoke-Native: pg_ctl starts the database through a cmd.exe that inherits every handle, so it would keep
  # the pipe Invoke-Native reads open for as long as the database runs, and this script would wait forever (found under
  # Wine). Its output goes to files instead, and only pg_ctl itself is waited for.
  $out = Join-Path $Data 'pg_ctl.out.log'
  $err = Join-Path $Data 'pg_ctl.err.log'
  $pgArgs = @('start', '-D', "`"$PgData`"", '-l', "`"$PgLog`"", '-w', '-t', '90', '-s')
  $common = @{ FilePath = (Join-Path $PgBin 'pg_ctl.exe'); ArgumentList = $pgArgs; PassThru = $true; RedirectStandardOutput = $out; RedirectStandardError = $err }
  # in this window (portable): the database shares the console, so closing the window stops it too
  if ($Action -eq 'run') { $p = Start-Process @common -NoNewWindow } else { $p = Start-Process @common -WindowStyle Hidden }
  # Windows PowerShell 5.1 hands back an ExitCode of $null (and the start counted as failed, on the CI's Windows) unless
  # the handle was asked for before the process ended; pwsh 7 under Wine did not show it. A code still missing is
  # settled by asking pg_ctl itself.
  $null = $p.Handle
  $p.WaitForExit()
  $code = $p.ExitCode
  if ($null -eq $code) { if (Test-DatabaseRunning) { $code = 0 } else { $code = 1 } }
  if ($code -ne 0) {
    $why = @($out, $err, $PgLog) | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Content -LiteralPath $_ -Tail 5 }
    throw "o banco de dados não iniciou (pg_ctl: $code).$([Environment]::NewLine)$($why -join [Environment]::NewLine)"
  }
}

function Stop-Database {
  if (Test-DatabaseRunning) {
    [void](Invoke-Native (Join-Path $PgBin 'pg_ctl.exe') @('stop', '-D', $PgData, '-m', 'fast', '-w', '-t', '60', '-s'))
  }
}

# The bundled PostgreSQL major version ("18"), read from pg_ctl itself.
function Get-BundledMajor {
  $r = Invoke-Native (Join-Path $PgBin 'pg_ctl.exe') @('--version')
  if ($r.Text -match '(\d+)\.\d+') { return $Matches[1] }
  throw "não foi possível ler a versão do PostgreSQL em $PgBin ($($r.Text))"
}

# Creates the database the first time (initdb, the settings, the database itself). A cluster of another major version is
# never touched: its files only open with that version, and pg_upgrade is a step a person must choose.
function Initialize-Database($s) {
  $versionFile = Join-Path $PgData 'PG_VERSION'
  if (Test-Path -LiteralPath $versionFile) {
    $have = (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim()
    $want = Get-BundledMajor
    if ($have -ne $want) {
      throw "o banco em $PgData é do PostgreSQL $have e esta versão do Pindrel Server traz o PostgreSQL $want. Instale de novo a versão anterior, faça um backup (pg_dump) e restaure nesta."
    }
    return $false
  }
  foreach ($k in 'DB_USER', 'DB_PASSWORD', 'DB_NAME', 'DB_PORT') {
    if (-not $s[$k]) { throw "falta $k no server.env" }
  }
  # a folder without PG_VERSION is the leftover of a first start that failed half-way: initdb needs it empty
  if (Test-Path -LiteralPath $PgData) { Remove-Item -LiteralPath $PgData -Recurse -Force }
  $pw = Join-Path $Data 'pg-password.tmp'
  [IO.File]::WriteAllText($pw, $s['DB_PASSWORD'])
  try {
    $r = Invoke-Native (Join-Path $PgBin 'initdb.exe') @('-D', $PgData, '-U', $s['DB_USER'], "--pwfile=$pw", '-E', 'UTF8', '--locale=C', '--auth=scram-sha-256')
  } finally {
    Remove-Item -LiteralPath $pw -Force -ErrorAction SilentlyContinue
  }
  if ($r.Code -ne 0) { throw "não foi possível criar o banco de dados (initdb): $($r.Text)" }
  # only this machine, and the same small memory budget as compose.yml
  Add-Content -LiteralPath (Join-Path $PgData 'postgresql.conf') -Encoding ASCII -Value @(
    '',
    '# Pindrel Server',
    "listen_addresses = '127.0.0.1'",
    "port = $([int]$s['DB_PORT'])",
    'shared_buffers = 32MB',
    'work_mem = 4MB',
    'maintenance_work_mem = 16MB',
    'max_connections = 20',
    'max_worker_processes = 4',
    'max_parallel_workers_per_gather = 0',
    'autovacuum_max_workers = 2'
  )
  Start-Database $s
  if ($s['DB_NAME'] -ne 'postgres') {
    $env:PGPASSWORD = $s['DB_PASSWORD']
    try {
      $r = Invoke-Native (Join-Path $PgBin 'createdb.exe') @('-h', '127.0.0.1', '-p', $s['DB_PORT'], '-U', $s['DB_USER'], $s['DB_NAME'])
    } finally {
      Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }
    if ($r.Code -ne 0) {
      Stop-Database
      Remove-Item -LiteralPath $PgData -Recurse -Force -ErrorAction SilentlyContinue
      throw "não foi possível criar a base $($s['DB_NAME']): $($r.Text)"
    }
  }
  return $true
}

function Get-ServerProcess {
  Get-Process pindrel-server -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Exe }
}

function Stop-Server {
  # the start action retries a server that dies; this file tells it that this stop is on purpose
  if (Test-Path -LiteralPath $Data) { New-Item -ItemType File -Force -Path $Flag | Out-Null }
  Get-ServerProcess | Stop-Process -Force
}

function Get-Settings {
  if (-not (Test-Path -LiteralPath $Conf)) { throw "não existe $Conf" }
  return Read-Settings $Conf
}

function Show-Addresses([int]$Port) {
  Write-Host ''
  Write-Host "Abra no navegador deste computador: http://localhost:$Port"
  $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { $_.IPAddress }
  foreach ($ip in $ips) { Write-Host "Ou, de outro aparelho da rede: http://${ip}:$Port" }
  Write-Host ''
}

function Invoke-Action {
  switch ($Action) {
    'stop' {
      Stop-Server
      if (Test-Path -LiteralPath $Conf) { if (Test-Embedded (Read-Settings $Conf)) { Stop-Database } }
      return 0
    }
    'init' {
      New-PortableSettings
      $s = Get-Settings
      if (Test-Embedded $s) {
        [void](Initialize-Database $s)
        Stop-Database
      }
      return 0
    }
    'run' {
      New-PortableSettings
      $s = Get-Settings
      if (Get-ServerProcess) { Write-Host 'O servidor já está rodando. Para parar, use parar.cmd.'; return 0 }
      if (Test-Embedded $s) {
        if (-not (Test-Path -LiteralPath $PgData)) { Write-Host 'Primeira vez: criando o banco de dados (leva alguns segundos)...' }
        if (-not (Initialize-Database $s)) { Start-Database $s }
      }
      Set-Location -LiteralPath $Data
      # the lock only covers getting the database up: held while the server runs, it kept parar.cmd waiting (found under Wine)
      Unlock
      Show-Addresses ([int]$s['PORT'])
      Write-Host 'Para parar, feche esta janela ou aperte Ctrl+C.'
      try {
        # Out-Host: whatever the server prints goes to this window, never into the result of this function
        & $Exe --config $Conf | Out-Host
      } finally {
        if (Test-Embedded $s) { Stop-Database }
      }
      return 0
    }
    'start' {
      $s = Get-Settings
      if (Get-ServerProcess) { return 0 }
      # someone else already serves on that port (an install for all users, started by another person, or another program)
      if ($s['PORT'] -and -not (Test-PortFree ([int]$s['PORT']))) {
        Say "A porta $($s['PORT']) já está em uso por outro programa, então o servidor do Pindrel não foi iniciado. Troque PORT no server.env."
        return 1
      }
      Remove-Item -LiteralPath $Flag -ErrorAction SilentlyContinue
      if (Test-Embedded $s) {
        if (-not (Initialize-Database $s)) { Start-Database $s }
      }
      for ($i = 1; $i -le 6; $i++) {
        if (-not (Test-Path -LiteralPath $Exe)) { return 0 }
        $p = Start-Process -FilePath $Exe -ArgumentList '--config', "`"$Conf`"" -WorkingDirectory $Data -WindowStyle Hidden -PassThru `
          -RedirectStandardOutput (Join-Path $Data 'server.out.log') -RedirectStandardError $Log
        # up for 20 s: it started (it tries the database for ~25 s before giving up, so a dead database shows up here too)
        if (-not $p.WaitForExit(20000)) { return 0 }
        if (Test-Path -LiteralPath $Flag) { return 0 }
        Start-Sleep -Seconds 4
      }
      $why = ''
      if (Test-Path -LiteralPath $Log) { $why = (Get-Content -LiteralPath $Log -Encoding UTF8 -Tail 4) -join [Environment]::NewLine }
      Say ('O servidor do Pindrel não conseguiu iniciar.' + [Environment]::NewLine + [Environment]::NewLine + $why)
      return 1
    }
  }
}

# Two starts at once (the Startup shortcut and a double click) must not both create the database: the lock covers getting
# the database up and the server launched, never the time the server runs.
function Unlock {
  if ($script:owned) {
    $mutex.ReleaseMutex()
    $script:owned = $false
  }
}

$hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Data.ToLowerInvariant()))).Replace('-', '')
$mutex = New-Object System.Threading.Mutex($false, "Local\PindrelServer-$($hash.Substring(0, 16))")
$script:owned = $mutex.WaitOne(0)
# a stop waits for a start that is still creating the database (it takes seconds) instead of racing it
if (-not $script:owned -and $Action -eq 'stop') { $script:owned = $mutex.WaitOne(120000) }
if (-not $script:owned) {
  if ($Action -eq 'stop') {
    Say 'O servidor do Pindrel está sendo iniciado há mais de dois minutos e não pôde ser parado agora. Tente de novo.'
    exit 1
  }
  Write-Host 'O servidor já está sendo iniciado ou parado.'
  exit 0
}
$verb = @{ start = 'iniciar'; run = 'iniciar'; stop = 'parar'; init = 'preparar' }
$code = 1
try {
  $code = Invoke-Action
} catch {
  Say ('Erro ao ' + $verb[$Action] + ' o servidor do Pindrel: ' + $_.Exception.Message)
  $code = 1
} finally {
  Unlock
}
# anything a function let slip into its output would make $code an array: the last value is the code
exit [int]($code | Select-Object -Last 1)
