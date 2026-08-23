<#
.SYNOPSIS
WSL に本リポジトリの環境を構築する。取得から利用可能な状態までを一度に行う。

.DESCRIPTION
Windows 上で本リポジトリの環境を使うための入り口である。以下を順に行う。

  1. 配布イメージを取得し、固定した sha256 と照合する
  2. wsl --install --from-file で登録する
  3. 利用者を用意し、リポジトリを取得する
  4. scripts/wsl-provision.sh の段 system を root で実行する
     (/etc/wsl.conf、sudo、Nix、system の構成)
  5. 設定の反映のためディストリビューションを停止する
  6. scripts/wsl-provision.sh の段 home を利用者で実行する
     (make check と make hm-switch)

判断を伴う処理は scripts/wsl-provision.sh にある。本ファイルは静的解析の対象外で
あるため、内容を最小限に保つ。ここに残るのは、provision がまだ存在しない時点で
必要となる呼び出し (利用者の作成とリポジトリの取得) だけである。

経路は 2 つある。

  nixos   NixOS-WSL の配布イメージを登録する。system の構成まで flake で宣言的に
          管理する。設定は nix/wsl.nix が持つ
  ubuntu  Ubuntu LTS の配布イメージを登録する。Nix は provision が導入する。
          system は宣言的にならないが、追加の入力を必要としない

イメージはバージョンと sha256 で固定してある。配布元の隣に置かれたチェックサム
ファイルとの照合は、配布物と同時に差し替えられるため検証にならない。値は本文に
固定し、更新は scripts/update-pins.sh wsl-image で行う。

登録した環境は Windows 側から隔離する。Windows のドライブのマウント、Windows の
PATH の流入、Windows の実行ファイルの起動をいずれも無効化する。成立しているかは
scripts/check-wsl-isolation.sh が検査し、手順 6 の make check に含まれる。

各手順は既に済んでいれば飛ばす。失敗した場合はそのまま再実行できる。イメージは
.work\wsl に保存し、sha256 が一致する場合は再取得しない。

.PARAMETER Distro
登録するディストリビューション。nixos または ubuntu。既定は nixos。

.PARAMETER Name
WSL に登録する名前。既定はディストリビューションごとの既定値。

.PARAMETER Location
仮想ディスクの配置先。既定は wsl の既定値に従う。

.PARAMETER Ref
取得するリポジトリの ref。既定は main。

.PARAMETER Unregister
登録を解除する。仮想ディスクごと削除される。取得済みのイメージは残る。

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\wsl-bootstrap.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\wsl-bootstrap.ps1 -Distro ubuntu

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\wsl-bootstrap.ps1 -Unregister -Name NixOS
#>

[CmdletBinding()]
param(
  [ValidateSet('nixos', 'ubuntu')]
  [string]$Distro = 'nixos',

  [string]$Name,

  [string]$Location,

  [string]$Ref = 'main',

  [switch]$Unregister
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Invoke-WebRequest の進捗表示は大きなファイルの取得を著しく遅くする。
$ProgressPreference = 'SilentlyContinue'

# Windows PowerShell 5.1 では既定のプロトコルが古い場合がある。
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# WSL 上の利用者。scripts/wsl-provision.sh の PROVISION_USER と一致させる。
$User = 'nixos'

$RepoUrl = 'https://github.com/sabas0ba/dotfiles.git'
$RepoParent = "/home/$User/repos"
$RepoPath = "$RepoParent/dotfiles"

# --- 固定した配布イメージ ----------------------------------------------------
#
# 更新は scripts/update-pins.sh wsl-image <distro> <version> <url> <sha256> で行う。
# 値の取得元は同スクリプトの --help に記載してある。
$Images = @{
  nixos  = @{
    Version     = '2605.7.2'
    Url         = 'https://github.com/nix-community/NixOS-WSL/releases/download/2605.7.2/nixos.wsl'
    Sha256      = 'e7180ad555fdcb8e1e057e2ef056de467603a5e502ff8531053738371be3f6b9'
    DefaultName = 'NixOS'
  }
  ubuntu = @{
    Version     = '24.04.4'
    Url         = 'https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-wsl-amd64.wsl'
    Sha256      = '9b2f7730dc68227dd04a9f3e5eab86ad85caf556b8606ad94f1f29ff5c4fd3f5'
    DefaultName = 'Ubuntu-24.04'
  }
}

# wsl.exe を実行し、終了コードを返す。
#
# $ErrorActionPreference = 'Stop' のもとで native コマンドの stderr を扱うと、
# Windows PowerShell 5.1 は 1 行ごとに ErrorRecord (NativeCommandError) を作る。
# これは終了コードが 0 であっても発生し、Stop のもとでは実行が中断される。wsl.exe は
# 正常時にも警告を stderr へ出すため、この間だけ Continue に下げ、成否は終了コード
# だけで判断する。
function Start-Wsl {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$Quiet
  )

  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    # 出力はコンソールへ直接流す。関数の戻り値に混ざると、呼び出し側が受け取るのは
    # 終了コードではなく出力全体と終了コードの配列になる。
    if ($Quiet) {
      & wsl.exe @Arguments 2>&1 | Out-Null
    }
    else {
      & wsl.exe @Arguments | Out-Host
    }
  }
  finally {
    $ErrorActionPreference = $previous
  }

  return $LASTEXITCODE
}

function Invoke-Wsl {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  $code = Start-Wsl -Arguments $Arguments
  if ($code -ne 0) {
    throw "wsl.exe の実行に失敗しました (終了コード $code): wsl $($Arguments -join ' ')"
  }
}

# 成否だけを見る。失敗を例外にしないため Invoke-Wsl とは分けてある。
function Test-Wsl {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  return ((Start-Wsl -Arguments $Arguments -Quiet) -eq 0)
}

function Test-WslRegistered {
  param([Parameter(Mandatory = $true)][string]$DistroName)

  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $registered = & wsl.exe --list --quiet
  }
  finally {
    $ErrorActionPreference = $previous
  }

  if ($LASTEXITCODE -ne 0) {
    return $false
  }

  # wsl.exe は UTF-16LE で出力する。PowerShell 5.1 はこれをコンソールの
  # コードページとして復号するため、各文字の間に NUL が残る。名前は ASCII の
  # 範囲であるため、NUL を除くと正しい名前が得られる。
  $names = $registered -split "`r?`n" | ForEach-Object { ($_ -replace "`0", '').Trim() }
  return ($names -contains $DistroName)
}

function Get-PinnedImage {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Image,
    [Parameter(Mandatory = $true)][string]$Path
  )

  if (Test-Path -LiteralPath $Path) {
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -eq $Image.Sha256.ToUpperInvariant()) {
      Write-Host "  ok      取得済みのイメージを使用する ($Path)"
      return
    }
    Write-Host '  再取得  既存のイメージが固定した sha256 と一致しない'
    Remove-Item -LiteralPath $Path -Force
  }

  Write-Host "  取得    $($Image.Url)"
  Invoke-WebRequest -Uri $Image.Url -OutFile $Path -UseBasicParsing

  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  $expected = $Image.Sha256.ToUpperInvariant()
  if ($actual -ne $expected) {
    Remove-Item -LiteralPath $Path -Force
    throw "sha256 が一致しません。期待値 $expected 実際 $actual"
  }
  Write-Host '  ok      sha256 が固定した値と一致する'
}

# --- 実行 --------------------------------------------------------------------

$image = $Images[$Distro]
if (-not $Name) {
  $Name = $image.DefaultName
}

if ($Unregister) {
  if (-not (Test-WslRegistered -DistroName $Name)) {
    Write-Host "$Name は登録されていません。"
    return
  }
  Write-Host "  解除    $Name の登録を解除する (仮想ディスクごと削除される)"
  Invoke-Wsl -Arguments @('--unregister', $Name)
  Write-Host '取得済みのイメージは .work\wsl に残っている。'
  return
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$workDir = Join-Path $repoRoot '.work\wsl'
$imagePath = Join-Path $workDir "$Distro-$($image.Version).wsl"

Write-Host "ディストリビューション: $Distro $($image.Version)"
Write-Host "登録名: $Name"
Write-Host "リポジトリ: $RepoUrl ($Ref) -> $RepoPath"
Write-Host ''

# --- 1. 取得と照合 ---
if (-not (Test-Path -LiteralPath $workDir)) {
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null
}
Get-PinnedImage -Image $image -Path $imagePath

# --- 2. 登録 ---
# WSL 2.4.4 以降は .wsl 形式をそのまま登録できる。それより古い場合は本コマンドが
# 失敗するため、WSL を更新する (wsl --update)。
if (Test-WslRegistered -DistroName $Name) {
  Write-Host "  ok      $Name は既に登録されている"
}
else {
  $installArgs = @('--install', '--from-file', $imagePath, '--name', $Name)
  if ($Location) {
    $installArgs += @('--location', $Location)
  }
  Write-Host "  登録    wsl $($installArgs -join ' ')"
  Invoke-Wsl -Arguments $installArgs
}

# --- 3. 利用者とリポジトリ ---
# provision はリポジトリの中にあるため、この 2 つだけは先に行う必要がある。
if (-not (Test-Wsl -Arguments @('-d', $Name, '-u', 'root', '--', 'id', '-u', $User))) {
  Write-Host "  作成    利用者 $User"
  Invoke-Wsl -Arguments @(
    '-d', $Name, '-u', 'root', '--',
    'useradd', '--create-home', '--shell', '/bin/bash', $User
  )
}

if (Test-Wsl -Arguments @('-d', $Name, '-u', $User, '--', 'test', '-d', "$RepoPath/.git")) {
  Write-Host "  ok      リポジトリは取得済み ($RepoPath)"
}
else {
  Write-Host "  取得    $RepoUrl ($Ref)"
  Invoke-Wsl -Arguments @('-d', $Name, '-u', $User, '--', 'mkdir', '-p', $RepoParent)

  if (Test-Wsl -Arguments @('-d', $Name, '-u', $User, '--', 'sh', '-lc', 'command -v git')) {
    Invoke-Wsl -Arguments @(
      '-d', $Name, '-u', $User, '--',
      'git', 'clone', '--branch', $Ref, $RepoUrl, $RepoPath
    )
  }
  else {
    # NixOS-WSL の配布イメージには git が含まれない。Nix から取る。gitMinimal は
    # perl や curl を伴わないため、この 1 回のために取得する量が小さい。
    Invoke-Wsl -Arguments @(
      '-d', $Name, '-u', $User, '--',
      'nix-shell', '-p', 'gitMinimal', '--run', "git clone --branch $Ref $RepoUrl $RepoPath"
    )
  }
}

# --- 4. 段 system ---
Write-Host '  構成    provision の段 system を実行する'
Invoke-Wsl -Arguments @(
  '-d', $Name, '-u', 'root', '--',
  'sh', '-lc', "$RepoPath/scripts/wsl-provision.sh system $Distro"
)

# --- 5. 反映のための停止 ---
# /etc/wsl.conf は起動時にのみ読まれる。--shutdown は他のディストリビューションも
# 停止させるため使用しない。
Write-Host "  再起動  $Name を停止して設定を反映する"
Invoke-Wsl -Arguments @('--terminate', $Name)

# --- 6. 段 home ---
Write-Host '  構成    provision の段 home を実行する'
Invoke-Wsl -Arguments @(
  '-d', $Name, '-u', $User, '--',
  'sh', '-lc', "$RepoPath/scripts/wsl-provision.sh home $Distro"
)

Write-Host ''
Write-Host "$Name の構築を終えました。"
Write-Host "  wsl -d $Name"
