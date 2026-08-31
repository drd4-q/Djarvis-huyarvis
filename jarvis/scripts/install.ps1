# =======================================================================
#  JARVIS AI ASSISTANT - GUI & CLI INSTALLER / SETUP SCRIPT (PowerShell)
# =======================================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Split-Path -Parent $ScriptDir
Set-Location $ProjectDir

$ModelsDir = Join-Path $ProjectDir "models"
$BinDir = Join-Path $ProjectDir "bin"
$ZigOutDir = Join-Path $ProjectDir "zig-out\bin"

# URLs for models and binaries
$LLM_URL = "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"
$LLM_FILE = "qwen2.5-3b-instruct-q4_k_m.gguf"

$WHISPER_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
$WHISPER_FILE = "ggml-base.bin"

$PIPER_ONNX_URL = "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/dmitri/medium/ru_RU-dmitri-medium.onnx"
$PIPER_JSON_URL = "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/dmitri/medium/ru_RU-dmitri-medium.onnx.json"
$PIPER_ONNX_FILE = "ru_RU-dmitri-medium.onnx"
$PIPER_JSON_FILE = "ru_RU-dmitri-medium.onnx.json"

function Download-FileWithProgress($url, $destPath, $label) {
    if (Test-Path $destPath) {
        $size = (Get-Item $destPath).Length
        if ($size -gt 1024) {
            Write-Host "  [+] $label already downloaded: $destPath" -ForegroundColor Green
            return
        }
    }

    Write-Host "  [~] Downloading $label..." -ForegroundColor Cyan
    Write-Host "      URL: $url" -ForegroundColor Gray
    Write-Host "      Dest: $destPath" -ForegroundColor Gray

    $parent = Split-Path -Parent $destPath
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    # Method 1: curl.exe (built-in Windows 10/11)
    $curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curlCmd) {
        try {
            & curl.exe -L --fail --progress-bar -o "$destPath" "$url"
            if ($LASTEXITCODE -eq 0 -and (Test-Path $destPath) -and (Get-Item $destPath).Length -gt 1024) {
                Write-Host "  [OK] $label successfully downloaded!" -ForegroundColor Green
                return
            }
        } catch {}
    }

    # Method 2: BITS Transfer
    try {
        Start-BitsTransfer -Source $url -Destination $destPath -DisplayName "Jarvis: $label" -ErrorAction Stop
        if ((Test-Path $destPath) -and (Get-Item $destPath).Length -gt 1024) {
            Write-Host "  [OK] $label successfully downloaded via BITS!" -ForegroundColor Green
            return
        }
    } catch {}

    # Method 3: HttpWebRequest
    try {
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) JarvisInstaller/1.0"
        $req.AllowAutoRedirect = $true
        $req.Timeout = 600000
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($destPath)
        $stream.CopyTo($fs)
        $fs.Close()
        $stream.Close()
        $resp.Close()
        Write-Host "  [OK] $label successfully downloaded!" -ForegroundColor Green
    }
    catch {
        Write-Host "  [!] Download error: $_" -ForegroundColor Red
    }
}

function Create-AppShortcut($targetPath, $shortcutPath, $arguments = "", $description = "Jarvis AI Assistant", $iconPath = "") {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($shortcutPath)
    $Shortcut.TargetPath = $targetPath
    $Shortcut.Arguments = $arguments
    $Shortcut.WorkingDirectory = $ProjectDir
    $Shortcut.Description = $description
    if ($iconPath -and (Test-Path $iconPath)) {
        $Shortcut.IconLocation = $iconPath
    }
    $Shortcut.Save()
    Write-Host "  [OK] Shortcut created: $shortcutPath" -ForegroundColor Green
}

function Set-Autostart($enable) {
    $StartupDir = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Startup)
    $StartupLnk = Join-Path $StartupDir "Jarvis.lnk"
    $TargetBat = Join-Path $ScriptDir "run_all.bat"

    if ($enable) {
        Create-AppShortcut $TargetBat $StartupLnk "" "Jarvis AI Assistant Auto-start"
        Write-Host "  [+] Jarvis added to Windows Startup." -ForegroundColor Green
    } else {
        if (Test-Path $StartupLnk) {
            Remove-Item $StartupLnk -Force
            Write-Host "  [-] Jarvis removed from Windows Startup." -ForegroundColor Yellow
        }
    }
}

function Add-Path-To-Environment($dirPath) {
    try {
        $curPath = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Process)
        if ($curPath -notlike "*$dirPath*") {
            $newProcPath = $dirPath + ";" + $curPath
            [System.Environment]::SetEnvironmentVariable("PATH", $newProcPath, [System.EnvironmentVariableTarget]::Process)
        }

        $userPath = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
        if ($userPath -notlike "*$dirPath*") {
            $newUserPath = $dirPath
            if ($userPath -and $userPath.Length -gt 0) {
                $newUserPath = $userPath + ";" + $dirPath
            }
            [System.Environment]::SetEnvironmentVariable("PATH", $newUserPath, [System.EnvironmentVariableTarget]::User)
            Write-Host "  [+] Added '$dirPath' to User PATH environment variable." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [!] Could not update registry PATH: $_" -ForegroundColor Yellow
    }
}

function Ensure-Zig-Installed {
    Write-Host ""
    Write-Host "[0/4] Checking Zig compiler in system:" -ForegroundColor Yellow

    $zigCmd = Get-Command zig -ErrorAction SilentlyContinue
    if ($zigCmd) {
        $zigVer = (& zig version) 2>$null
        Write-Host "  [+] Zig already installed: $zigVer ($($zigCmd.Source))" -ForegroundColor Green
        return $true
    }

    $LocalZigDir = Join-Path $ProjectDir "tools\zig"
    $LocalZigExe = Join-Path $LocalZigDir "zig.exe"
    
    if (-not (Test-Path $LocalZigExe)) {
        $found = Get-ChildItem -Path $LocalZigDir -Filter "zig.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $LocalZigExe = $found.FullName
            $LocalZigDir = $found.DirectoryName
        }
    }

    if (Test-Path $LocalZigExe) {
        Write-Host "  [+] Zig found in local directory: $LocalZigExe" -ForegroundColor Green
        Add-Path-To-Environment $LocalZigDir
        return $true
    }

    Write-Host "  [~] Zig not found. Starting automatic installation..." -ForegroundColor Cyan

    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "  [~] Attempting Zig install via winget..." -ForegroundColor Cyan
        try {
            & winget install --id zig.zig -e --accept-source-agreements --accept-package-agreements --silent | Out-Null
            $uP = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
            $mP = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine)
            $comb = $uP + ";" + $mP
            [System.Environment]::SetEnvironmentVariable("PATH", $comb, [System.EnvironmentVariableTarget]::Process)
            
            $zigCmdAfter = Get-Command zig -ErrorAction SilentlyContinue
            if ($zigCmdAfter) {
                Write-Host "  [OK] Zig successfully installed via winget!" -ForegroundColor Green
                return $true
            }
        } catch {}
    }

    $ZigZipUrl = "https://ziglang.org/download/0.13.0/zig-windows-x86_64-0.13.0.zip"
    $ZigZipDest = Join-Path $ProjectDir "tools\zig-windows.zip"
    $ToolsDir = Join-Path $ProjectDir "tools"

    if (-not (Test-Path $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null }

    Write-Host "  [~] Downloading Zig compiler archive from ziglang.org..." -ForegroundColor Cyan
    Download-FileWithProgress $ZigZipUrl $ZigZipDest "Zig Compiler (Windows x64)"

    if (Test-Path $ZigZipDest) {
        Write-Host "  [~] Extracting Zig archive..." -ForegroundColor Cyan
        try {
            Expand-Archive -Path $ZigZipDest -DestinationPath $ToolsDir -Force
            Remove-Item $ZigZipDest -Force -ErrorAction SilentlyContinue

            $foundExe = Get-ChildItem -Path $ToolsDir -Filter "zig.exe" -Recurse | Select-Object -First 1
            if ($foundExe) {
                $actualZigDir = $foundExe.DirectoryName
                Add-Path-To-Environment $actualZigDir
                Write-Host "  [OK] Zig installed and configured in PATH!" -ForegroundColor Green
                return $true
            }
        } catch {
            Write-Host "  [!] Error extracting Zig archive: $_" -ForegroundColor Red
        }
    }

    Write-Host "  [!] Automatic Zig installation failed. Please install from https://ziglang.org" -ForegroundColor Yellow
    return $false
}

function Perform-Installation($dlLLM, $dlAudio, $addAutostart, $createDesktop, $installZig = $true) {
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "            JARVIS AI - INSTALLATION PROCESS           " -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ""

    if ($installZig) {
        Ensure-Zig-Installed | Out-Null
    }

    if (-not (Test-Path $ModelsDir)) {
        New-Item -ItemType Directory -Path $ModelsDir -Force | Out-Null
    }

    if ($dlLLM) {
        Write-Host ""
        Write-Host "[1/4] LLM Model (Qwen2.5-3B-Instruct GGUF):" -ForegroundColor Yellow
        $dest = Join-Path $ModelsDir $LLM_FILE
        Download-FileWithProgress $LLM_URL $dest "LLM Qwen2.5-3B-Instruct"
    }

    if ($dlAudio) {
        Write-Host ""
        Write-Host "[2/4] Audio Models (Whisper STT + Piper TTS):" -ForegroundColor Yellow
        Download-FileWithProgress $WHISPER_URL (Join-Path $ModelsDir $WHISPER_FILE) "Whisper Base STT"
        Download-FileWithProgress $PIPER_ONNX_URL (Join-Path $ModelsDir $PIPER_ONNX_FILE) "Piper TTS ONNX"
        Download-FileWithProgress $PIPER_JSON_URL (Join-Path $ModelsDir $PIPER_JSON_FILE) "Piper TTS JSON Config"
    }

    Write-Host ""
    Write-Host "[3/4] Checking Jarvis Executable binary:" -ForegroundColor Yellow
    $JarvisExe = Join-Path $ZigOutDir "jarvis.exe"
    if (-not (Test-Path $JarvisExe)) {
        $JarvisExeLinux = Join-Path $ZigOutDir "jarvis"
        if (Test-Path $JarvisExeLinux) {
            Write-Host "  [+] Executable binary ready: $JarvisExeLinux" -ForegroundColor Green
        } else {
            Write-Host "  [~] Compiling jarvis via 'zig build'..." -ForegroundColor Cyan
            try {
                Set-Location $ProjectDir
                & zig build -Doptimize=ReleaseFast
                if (Test-Path $JarvisExe) {
                    Write-Host "  [OK] Build complete: $JarvisExe" -ForegroundColor Green
                }
            } catch {
                Write-Host "  [!] Warning: zig build failed or Zig not found." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  [+] Executable binary ready: $JarvisExe" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "[4/4] Configuring Shortcuts & Autostart:" -ForegroundColor Yellow
    if ($addAutostart) {
        Set-Autostart $true
    }

    if ($createDesktop) {
        $DesktopDir = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
        $DesktopLnk = Join-Path $DesktopDir "Jarvis AI.lnk"
        $TargetBat = Join-Path $ScriptDir "run_all.bat"
        Create-AppShortcut $TargetBat $DesktopLnk "" "Launch Jarvis AI Assistant"
    }

    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "           SETUP COMPLETED SUCCESSFULLY!               " -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "To start the assistant, run scripts\run_all.bat or Desktop shortcut." -ForegroundColor White
}

function Show-GUI-Installer {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Jarvis AI Assistant - Setup Wizard"
    $form.Size = New-Object System.Drawing.Size(520, 480)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Size = New-Object System.Drawing.Size(520, 70)
    $headerPanel.Dock = "Top"
    $headerPanel.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $form.Controls.Add($headerPanel)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "JARVIS AI ASSISTANT"
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object System.Drawing.Point(20, 12)
    $titleLabel.AutoSize = $true
    $headerPanel.Controls.Add($titleLabel)

    $subLabel = New-Object System.Windows.Forms.Label
    $subLabel.Text = "Components setup & automated configuration"
    $subLabel.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $subLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $subLabel.Location = New-Object System.Drawing.Point(22, 38)
    $subLabel.AutoSize = $true
    $headerPanel.Controls.Add($subLabel)

    $grpBox = New-Object System.Windows.Forms.GroupBox
    $grpBox.Text = " Installation Options "
    $grpBox.Location = New-Object System.Drawing.Point(20, 85)
    $grpBox.Size = New-Object System.Drawing.Size(465, 270)
    $form.Controls.Add($grpBox)

    $chkLLM = New-Object System.Windows.Forms.CheckBox
    $chkLLM.Text = "Download Qwen2.5-3B-Instruct Model (GGUF, ~1.9 GB)"
    $chkLLM.Location = New-Object System.Drawing.Point(20, 28)
    $chkLLM.Size = New-Object System.Drawing.Size(420, 24)
    $chkLLM.Checked = $true
    $grpBox.Controls.Add($chkLLM)

    $chkAudio = New-Object System.Windows.Forms.CheckBox
    $chkAudio.Text = "Download STT & TTS Models (Whisper + Piper, ~135 MB)"
    $chkAudio.Location = New-Object System.Drawing.Point(20, 62)
    $chkAudio.Size = New-Object System.Drawing.Size(420, 24)
    $chkAudio.Checked = $true
    $grpBox.Controls.Add($chkAudio)

    $chkZig = New-Object System.Windows.Forms.CheckBox
    $chkZig.Text = "Check and auto-install Zig compiler to PATH (if needed)"
    $chkZig.Location = New-Object System.Drawing.Point(20, 96)
    $chkZig.Size = New-Object System.Drawing.Size(420, 24)
    $chkZig.Checked = $true
    $chkZig.ForeColor = [System.Drawing.Color]::FromArgb(30, 64, 175)
    $grpBox.Controls.Add($chkZig)

    $chkDesktop = New-Object System.Windows.Forms.CheckBox
    $chkDesktop.Text = "Create Desktop shortcut"
    $chkDesktop.Location = New-Object System.Drawing.Point(20, 140)
    $chkDesktop.Size = New-Object System.Drawing.Size(420, 24)
    $chkDesktop.Checked = $true
    $grpBox.Controls.Add($chkDesktop)

    $chkAutostart = New-Object System.Windows.Forms.CheckBox
    $chkAutostart.Text = "Add Jarvis to Windows Startup (launch on logon)"
    $chkAutostart.Location = New-Object System.Drawing.Point(20, 175)
    $chkAutostart.Size = New-Object System.Drawing.Size(430, 24)
    $chkAutostart.Checked = $true
    $chkAutostart.ForeColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
    $grpBox.Controls.Add($chkAutostart)

    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = "Install"
    $btnInstall.Size = New-Object System.Drawing.Size(140, 38)
    $btnInstall.Location = New-Object System.Drawing.Point(345, 375)
    $btnInstall.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
    $btnInstall.ForeColor = [System.Drawing.Color]::White
    $btnInstall.FlatStyle = "Flat"
    $btnInstall.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $btnInstall.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnInstall)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Size = New-Object System.Drawing.Size(100, 38)
    $btnCancel.Location = New-Object System.Drawing.Point(235, 375)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $btnCancel.ForeColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $btnCancel.DialogResult = "Cancel"
    $form.Controls.Add($btnCancel)

    $btnInstall.Add_Click({
        $btnInstall.Enabled = $false
        $btnCancel.Enabled = $false
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

        $dlLLM = $chkLLM.Checked
        $dlAudio = $chkAudio.Checked
        $addAutostart = $chkAutostart.Checked
        $createDesktop = $chkDesktop.Checked
        $installZig = $chkZig.Checked

        $form.Close()
        Perform-Installation $dlLLM $dlAudio $addAutostart $createDesktop $installZig
    })

    [void]$form.ShowDialog()
}

try {
    Show-GUI-Installer
} catch {
    Write-Host "[Console Mode] Launching interactive setup..." -ForegroundColor Yellow
    $ansLLM = Read-Host "Download Qwen2.5-3B-Instruct model (~1.9 GB)? (Y/n)"
    $ansAudio = Read-Host "Download Whisper STT + Piper TTS models? (Y/n)"
    $ansZig = Read-Host "Check and install Zig in PATH (if needed)? (Y/n)"
    $ansDesktop = Read-Host "Create Desktop shortcut? (Y/n)"
    $ansAutostart = Read-Host "Add to Windows Startup? (Y/n)"

    $dlLLM = ($ansLLM -ne "n" -and $ansLLM -ne "N")
    $dlAudio = ($ansAudio -ne "n" -and $ansAudio -ne "N")
    $installZig = ($ansZig -ne "n" -and $ansZig -ne "N")
    $createDesktop = ($ansDesktop -ne "n" -and $ansDesktop -ne "N")
    $addAutostart = ($ansAutostart -ne "n" -and $ansAutostart -ne "N")

    Perform-Installation $dlLLM $dlAudio $addAutostart $createDesktop $installZig
}

