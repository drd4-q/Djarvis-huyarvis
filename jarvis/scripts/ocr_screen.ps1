[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try {
    [Windows.Media.Ocr.OcrEngine, Windows.Foundation.UniversalApiContract, ContentType = WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation.UniversalApiContract, ContentType = WindowsRuntime] | Out-Null
    [Windows.Storage.StorageFile, Windows.Foundation.UniversalApiContract, ContentType = WindowsRuntime] | Out-Null

    $screenPath = (Resolve-Path (Join-Path $PSScriptRoot "..\cache_screen.bmp")).Path
    if (-not (Test-Path $screenPath)) {
        Write-Output "Скриншот не найден"
        exit 0
    }

    $file = [Windows.Storage.StorageFile]::GetFileFromPathAsync($screenPath)
    while ($file.Status -eq "Started") { Start-Sleep -Milliseconds 10 }
    $fileObj = $file.GetResults()

    $stream = $fileObj.OpenAsync([Windows.Storage.FileAccessMode]::Read)
    while ($stream.Status -eq "Started") { Start-Sleep -Milliseconds 10 }
    $streamObj = $stream.GetResults()

    $decoder = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($streamObj)
    while ($decoder.Status -eq "Started") { Start-Sleep -Milliseconds 10 }
    $decoderObj = $decoder.GetResults()

    $bitmap = $decoderObj.GetSoftwareBitmapAsync()
    while ($bitmap.Status -eq "Started") { Start-Sleep -Milliseconds 10 }
    $bitmapObj = $bitmap.GetResults()

    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if (-not $engine) {
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new("ru"))
    }
    if (-not $engine) {
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new("en-US"))
    }

    $ocr = $engine.RecognizeAsync($bitmapObj)
    while ($ocr.Status -eq "Started") { Start-Sleep -Milliseconds 10 }
    $ocrResult = $ocr.GetResults()

    $lines = @()
    foreach ($l in $ocrResult.Lines) {
        $t = $l.Text.Trim()
        if ($t.Length -gt 1) {
            $lines += $t
        }
    }

    if ($lines.Count -gt 0) {
        $unique = $lines | Select-Object -Unique | Select-Object -First 35
        Write-Output ($unique -join "`n")
    } else {
        Write-Output "Текст не распознан"
    }
} catch {
    Write-Output "OCR Error: $_"
}
