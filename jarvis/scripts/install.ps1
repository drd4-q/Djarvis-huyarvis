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
        Write-Host "  [+] $label уже скачан: $destPath" -ForegroundColor Green
        return
    }

    Write-Host "  [~] Скачивание $label..." -ForegroundColor Cyan
    Write-Host "      URL: $url" -ForegroundColor Gray
    Write-Host "      Цель: $destPath" -ForegroundColor Gray

    $parent = Split-Path -Parent $destPath
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) JarvisInstaller/1.0")
        
        $totalBytes = 0
        $webClient.DownloadFile($url, $destPath)
        Write-Host "  [OK] $label успешно загружен!" -ForegroundColor Green
    }
    catch {
        Write-Host "  [!] Ошибка при скачивании $label: $_" -ForegroundColor Red
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
    Write-Host "  [OK] Ярлык создан: $shortcutPath" -ForegroundColor Green
}

function Set-Autostart($enable) {
    $StartupDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    $StartupLnk = Join-Path $StartupDir "Jarvis.lnk"
    $TargetBat = Join-Path $ScriptDir "run_all.bat"

    if ($enable) {
        Create-AppShortcut $TargetBat $StartupLnk "" "Jarvis AI Assistant Auto-start"
        Write-Host "  [+] Jarvis добавлен в автозагрузку Windows." -ForegroundColor Green
    } else {
        if (Test-Path $StartupLnk) {
            Remove-Item $StartupLnk -Force
            Write-Host "  [-] Jarvis удален из автозагрузки Windows." -ForegroundColor Yellow
        }
    }
}

function Perform-Installation($dlLLM, $dlAudio, $addAutostart, $createDesktop) {
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host "            НАЧАЛО УСТАНОВКИ JARVIS AI" -ForegroundColor Cyan
    Write-Host "=======================================================`n" -ForegroundColor Cyan

    # 1. Ensure models directory
    if (-not (Test-Path $ModelsDir)) {
        New-Item -ItemType Directory -Path $ModelsDir -Force | Out-Null
    }

    # 2. Download LLM
    if ($dlLLM) {
        Write-Host "`n[1/4] Языковая модель (Qwen2.5-3B-Instruct GGUF):" -ForegroundColor Yellow
        $dest = Join-Path $ModelsDir $LLM_FILE
        Download-FileWithProgress $LLM_URL $dest "LLM Qwen2.5-3B-Instruct"
    }

    # 3. Download Audio Models (Whisper + Piper)
    if ($dlAudio) {
        Write-Host "`n[2/4] Аудио-модели (Whisper STT + Piper TTS):" -ForegroundColor Yellow
        Download-FileWithProgress $WHISPER_URL (Join-Path $ModelsDir $WHISPER_FILE) "Whisper Base STT"
        Download-FileWithProgress $PIPER_ONNX_URL (Join-Path $ModelsDir $PIPER_ONNX_FILE) "Piper TTS ONNX"
        Download-FileWithProgress $PIPER_JSON_URL (Join-Path $ModelsDir $PIPER_JSON_FILE) "Piper TTS JSON Config"
    }

    # 4. Check & Compile Zig executable if needed
    Write-Host "`n[3/4] Проверка исполняемого файла Jarvis:" -ForegroundColor Yellow
    $JarvisExe = Join-Path $ZigOutDir "jarvis.exe"
    if (-not (Test-Path $JarvisExe)) {
        $JarvisExeLinux = Join-Path $ZigOutDir "jarvis"
        if (Test-Path $JarvisExeLinux) {
            Write-Host "  [+] Исполняемый файл собран: $JarvisExeLinux" -ForegroundColor Green
        } else {
            Write-Host "  [~] Сборка jarvis через 'zig build'..." -ForegroundColor Cyan
            try {
                Set-Location $ProjectDir
                & zig build -Doptimize=ReleaseFast
                if (Test-Path $JarvisExe) {
                    Write-Host "  [OK] Сборка успешно завершена: $JarvisExe" -ForegroundColor Green
                }
            } catch {
                Write-Host "  [!] Предупреждение: Zig не найден в PATH или сборка пропущена." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  [+] Исполняемый файл готов: $JarvisExe" -ForegroundColor Green
    }

    # 5. Shortcuts & Autostart
    Write-Host "`n[4/4] Настройка ярлыков и автозагрузки:" -ForegroundColor Yellow
    if ($addAutostart) {
        Set-Autostart $true
    }

    if ($createDesktop) {
        $DesktopDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
        $DesktopLnk = Join-Path $DesktopDir "Jarvis AI.lnk"
        $TargetBat = Join-Path $ScriptDir "run_all.bat"
        Create-AppShortcut $TargetBat $DesktopLnk "" "Запуск Jarvis AI Assistant"
    }

    Write-Host "`n=======================================================" -ForegroundColor Green
    Write-Host "         УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!" -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "Для запуска ассистента используйте scripts\run_all.bat" -ForegroundColor White
}

# ----------------- GUI Windows Forms Setup -----------------
function Show-GUI-Installer {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Jarvis AI Assistant — Мастер установки"
    $form.Size = New-Object System.Drawing.Size(520, 430)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    # Header Panel
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
    $subLabel.Text = "Настройка компонентов и автоматический запуск"
    $subLabel.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $subLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $subLabel.Location = New-Object System.Drawing.Point(22, 38)
    $subLabel.AutoSize = $true
    $headerPanel.Controls.Add($subLabel)

    # Group Box for Options
    $grpBox = New-Object System.Windows.Forms.GroupBox
    $grpBox.Text = " Компоненты и параметры установки "
    $grpBox.Location = New-Object System.Drawing.Point(20, 85)
    $grpBox.Size = New-Object System.Drawing.Size(465, 220)
    $form.Controls.Add($grpBox)

    # Checkboxes
    $chkLLM = New-Object System.Windows.Forms.CheckBox
    $chkLLM.Text = "Скачать модель Qwen2.5-3B-Instruct (GGUF, ~1.9 ГБ)"
    $chkLLM.Location = New-Object System.Drawing.Point(20, 30)
    $chkLLM.Size = New-Object System.Drawing.Size(420, 24)
    $chkLLM.Checked = $true
    $grpBox.Controls.Add($chkLLM)

    $chkAudio = New-Object System.Windows.Forms.CheckBox
    $chkAudio.Text = "Скачать модели STT и TTS (Whisper + Piper, ~135 МБ)"
    $chkAudio.Location = New-Object System.Drawing.Point(20, 65)
    $chkAudio.Size = New-Object System.Drawing.Size(420, 24)
    $chkAudio.Checked = $true
    $grpBox.Controls.Add($chkAudio)

    $chkDesktop = New-Object System.Windows.Forms.CheckBox
    $chkDesktop.Text = "Создать ярлык на Рабочем столе"
    $chkDesktop.Location = New-Object System.Drawing.Point(20, 110)
    $chkDesktop.Size = New-Object System.Drawing.Size(420, 24)
    $chkDesktop.Checked = $true
    $grpBox.Controls.Add($chkDesktop)

    $chkAutostart = New-Object System.Windows.Forms.CheckBox
    $chkAutostart.Text = "Добавить Jarvis в автозагрузку Windows (при входе в систему)"
    $chkAutostart.Location = New-Object System.Drawing.Point(20, 145)
    $chkAutostart.Size = New-Object System.Drawing.Size(430, 24)
    $chkAutostart.Checked = $true
    $chkAutostart.ForeColor = [System.Drawing.Color]::FromArgb(15, 118, 110)
    $grpBox.Controls.Add($chkAutostart)

    # Install Button
    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = "Установить"
    $btnInstall.Size = New-Object System.Drawing.Size(140, 38)
    $btnInstall.Location = New-Object System.Drawing.Point(345, 330)
    $btnInstall.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
    $btnInstall.ForeColor = [System.Drawing.Color]::White
    $btnInstall.FlatStyle = "Flat"
    $btnInstall.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $btnInstall.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnInstall)

    # Cancel Button
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Отмена"
    $btnCancel.Size = New-Object System.Drawing.Size(100, 38)
    $btnCancel.Location = New-Object System.Drawing.Point(235, 330)
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

        $form.Close()
        Perform-Installation $dlLLM $dlAudio $addAutostart $createDesktop
    })

    [void]$form.ShowDialog()
}

# Run GUI or Fallback to CLI
try {
    Show-GUI-Installer
} catch {
    Write-Host "[Console Mode] GUI недоступен. Запуск в интерактивном консольном режиме..." -ForegroundColor Yellow
    $ansLLM = Read-Host "Скачать модель Qwen2.5-3B-Instruct (~1.9 GB)? (Y/n)"
    $ansAudio = Read-Host "Скачать модели Whisper STT + Piper TTS? (Y/n)"
    $ansDesktop = Read-Host "Создать ярлык на Рабочем столе? (Y/n)"
    $ansAutostart = Read-Host "Добавить в автозагрузку Windows? (Y/n)"

    $dlLLM = ($ansLLM -ne 'n' -and $ansLLM -ne 'N')
    $dlAudio = ($ansAudio -ne 'n' -and $ansAudio -ne 'N')
    $createDesktop = ($ansDesktop -ne 'n' -and $ansDesktop -ne 'N')
    $addAutostart = ($ansAutostart -ne 'n' -and $ansAutostart -ne 'N')

    Perform-Installation $dlLLM $dlAudio $addAutostart $createDesktop
}
