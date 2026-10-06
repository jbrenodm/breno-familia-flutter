<#
  Instala o ambiente para desenvolver o breno-familia-flutter no Windows:
  Git, Flutter (canal stable), Android Studio e Visual Studio 2022 Community
  com a carga "Desktop development with C++". Também liga o Modo de Desenvolvedor
  (o Flutter precisa dele para os plugins no Windows).

  Uso (PowerShell como Administrador):
    powershell -ExecutionPolicy Bypass -File .\tool\instalar_ambiente_windows.ps1

  Pode rodar de novo sem problema: o que já estiver instalado é pulado.
#>
param(
  [string]$PastaFlutter = 'C:\src\flutter'
)
$ErrorActionPreference = 'Stop'

function Passo($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "    OK: $t" -ForegroundColor Green }

# --- Administrador ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Abra o PowerShell como Administrador e rode o script de novo.' }

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw 'winget não encontrado. Instale o "Instalador de Aplicativo" pela Microsoft Store e rode de novo.'
}

function Instalar($id, $nome, $extra = @()) {
  $lista = winget list --id $id --exact --accept-source-agreements 2>$null | Out-String
  if ($lista -match [regex]::Escape($id)) { Ok "$nome já instalado"; return }
  Passo "Instalando $nome"
  winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements @extra
  if ($LASTEXITCODE -ne 0) { throw "Falha ao instalar $nome (código $LASTEXITCODE)" }
  Ok $nome
}

function AtualizarPath {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

# --- 1. Git ---
Instalar 'Git.Git' 'Git'
AtualizarPath

# --- 2. Visual Studio 2022 Community + Desktop development with C++ ---
Instalar 'Microsoft.VisualStudio.2022.Community' 'Visual Studio 2022 Community (C++ para desktop)' @(
  '--override', '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended'
)
# Se o VS já existia sem a carga C++, acrescenta a carga.
$vsInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installer.exe"
$vsPath = "$env:ProgramFiles\Microsoft Visual Studio\2022\Community"
if ((Test-Path $vsInstaller) -and (Test-Path $vsPath)) {
  Passo 'Garantindo a carga "Desktop development with C++" no Visual Studio'
  Start-Process $vsInstaller -Wait -ArgumentList @(
    'modify', '--installPath', "`"$vsPath`"",
    '--add', 'Microsoft.VisualStudio.Workload.NativeDesktop', '--includeRecommended',
    '--passive', '--norestart'
  )
  Ok 'Carga C++ para desktop'
}

# --- 3. Android Studio ---
Instalar 'Google.AndroidStudio' 'Android Studio'

# --- 4. Flutter (stable) ---
if (Test-Path "$PastaFlutter\bin\flutter.bat") {
  Ok "Flutter já está em $PastaFlutter"
} else {
  Passo "Baixando o Flutter (stable) em $PastaFlutter"
  New-Item -ItemType Directory -Force -Path (Split-Path $PastaFlutter) | Out-Null
  git clone https://github.com/flutter/flutter.git -b stable $PastaFlutter
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao baixar o Flutter' }
  Ok 'Flutter baixado'
}
$bin = "$PastaFlutter\bin"
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $bin) {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$bin"), 'User')
  Ok 'Flutter adicionado ao PATH do usuário'
}
AtualizarPath

# --- 5. Modo de Desenvolvedor (links simbólicos dos plugins no Windows) ---
Passo 'Ligando o Modo de Desenvolvedor do Windows'
$chave = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
if (-not (Test-Path $chave)) { New-Item -Path $chave -Force | Out-Null }
Set-ItemProperty -Path $chave -Name 'AllowDevelopmentWithoutDevLicense' -Type DWord -Value 1
Ok 'Modo de Desenvolvedor'

# --- 6. Primeira execução do Flutter ---
Passo 'Preparando o Flutter (primeira execução demora alguns minutos)'
flutter config --no-analytics | Out-Null
flutter precache --windows --android
flutter doctor

Write-Host @'

==========================================================================
 Falta só o que precisa da sua mão (uma vez):

 1. Abra o Android Studio e conclua o assistente inicial (Standard).
    Ele baixa o Android SDK.
 2. No Android Studio: More Actions > SDK Manager > aba "SDK Tools" >
    marque "Android SDK Command-line Tools (latest)" > Apply.
 3. Feche e abra um PowerShell novo e rode:
       flutter doctor --android-licenses   (responda "y" a tudo)
       flutter doctor
    Tudo que importa deve ficar verde: Flutter, Windows, Android toolchain,
    Visual Studio. Chrome e "Connected device" podem ser ignorados.
 4. No VS Code, instale as extensões "Flutter" e "Dart".
==========================================================================
'@ -ForegroundColor Yellow
