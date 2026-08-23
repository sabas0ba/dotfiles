<#
.SYNOPSIS
WSL のディストリビューションを取得して登録し、Windows 側から隔離した状態にする。

.DESCRIPTION
本リポジトリの環境を Windows 上で使用するための最初の一歩を担う。以降の手順
(Nix の導入、リポジトリの取得、nixos-rebuild / home-manager の適用) は README の
「Windows (WSL)」を参照する。

経路は 2 つある。

  nixos   NixOS-WSL の配布イメージを登録する。system の構成まで flake で宣言的に
          管理する。以降の設定は nix/wsl.nix が持つ
  ubuntu  Ubuntu LTS の配布イメージを登録する。Nix は README の導入手順で入れる。
          system は宣言的にならないが、追加の入力を必要としない

イメージはバージョンと sha256 で固定してある。配布元の隣に置かれたチェックサム
ファイルとの照合は、配布物と同時に差し替えられるため検証にならない。値は本文に
固定し、更新は scripts/update-pins.sh wsl-image で行う。

登録の直後に /etc/wsl.conf を配置し、Windows のドライブのマウント、Windows の
PATH の流入、Windows の実行ファイルの起動をいずれも無効化する。これは最初の対話
セッションより前に隔離を成立させるためである。NixOS では以降 nix/wsl.nix が同じ
内容を宣言的に生成する。成立しているかは scripts/check-wsl-isolation.sh が検査する。

イメージは .work/wsl 以下に保存する。sha256 が一致する場合は再取得しない。中断
した場合はそのまま再実行できる。破棄する場合は .work/wsl を削除する。

.PARAMETER Distro
登録するディストリビューション。nixos または ubuntu。既定は nixos。

.PARAMETER Name
WSL に登録する名前。既定はディストリビューションごとの既定値。

.PARAMETER Location
仮想ディスクの配置先。既定は wsl の既定値に従う。

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\wsl-bootstrap.ps1 -Distro nixos

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\wsl-bootstrap.ps1 -Distro ubuntu -Name Ubuntu-dev
#>

[CmdletBinding()]
param(
  [ValidateSet('nixos', 'ubuntu')]
  [string]$Distro = 'nixos',

  [string]$Name,

  [string]$Location
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Invoke-WebRequest の進捗表示は大きなファイルの取得を著しく遅くする。
$ProgressPreference = 'SilentlyContinue'

# Windows PowerShell 5.1 では既定のプロトコルが古い場合がある。
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

# --- 隔離の設定 --------------------------------------------------------------
#
# nix/wsl.nix の wsl.wslConf と同じ内容である。NixOS では初回の nixos-rebuild 以降
# そちらが正本となる。両者が満たすべき結果は scripts/check-wsl-isolation.sh が定義する。
$WslConfLines = @(
  '# WSL を Windows 側から隔離する。scripts/wsl-bootstrap.ps1 が配置した。'
  '# NixOS では nix/wsl.nix が本ファイルを生成するため、直接編集しても switch で戻る。'
  '[automount]'
  'enabled = false'
  '[interop]'
  'enabled = false'
  'appendWindowsPath = false'
)

function Invoke-Wsl {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  & wsl.exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "wsl.exe の実行に失敗しました (終了コード $LASTEXITCODE): wsl $($Arguments -join ' ')"
  }
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
    Write-Host "  再取得  既存のイメージが固定した sha256 と一致しない"
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
  Write-Host "  ok      sha256 が固定した値と一致する"
}

# --- 実行 --------------------------------------------------------------------

$image = $Images[$Distro]
if (-not $Name) {
  $Name = $image.DefaultName
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$workDir = Join-Path $repoRoot '.work\wsl'
$imagePath = Join-Path $workDir "$Distro-$($image.Version).wsl"

Write-Host "ディストリビューション: $Distro $($image.Version)"
Write-Host "登録名: $Name"
Write-Host ''

if (-not (Test-Path -LiteralPath $workDir)) {
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null
}

$registered = & wsl.exe --list --quiet
if ($LASTEXITCODE -eq 0 -and ($registered -split "`r?`n" | ForEach-Object { $_.Trim() }) -contains $Name) {
  throw "$Name は既に登録されています。作り直す場合は wsl --unregister $Name を実行してください。"
}

Get-PinnedImage -Image $image -Path $imagePath

# WSL 2.4.4 以降は .wsl 形式をそのまま登録できる。それより古い場合は本コマンドが
# 失敗するため、WSL を更新する (wsl --update)。
$installArgs = @('--install', '--from-file', $imagePath, '--name', $Name)
if ($Location) {
  $installArgs += @('--location', $Location)
}
Write-Host "  登録    wsl $($installArgs -join ' ')"
Invoke-Wsl -Arguments $installArgs

# 隔離を最初の対話セッションより前に成立させる。sh -c の位置引数として行を渡し、
# リダイレクトを Linux 側で行う。PowerShell 側のリダイレクトでは Windows の
# ファイルに書き出されてしまうため。
Write-Host '  設定    /etc/wsl.conf を配置する'
$confArgs = @(
  '-d', $Name, '-u', 'root', '--',
  'sh', '-c', 'printf "%s\n" "$@" > /etc/wsl.conf', 'sh'
) + $WslConfLines
Invoke-Wsl -Arguments $confArgs

# /etc/wsl.conf は起動時にのみ読まれる。反映のため一度停止する。
Write-Host '  再起動  設定の反映のためディストリビューションを停止する'
Invoke-Wsl -Arguments @('--terminate', $Name)

Write-Host ''
Write-Host "$Name を登録しました。続きの手順は README の「Windows (WSL)」を参照してください。"
Write-Host "  wsl -d $Name"
