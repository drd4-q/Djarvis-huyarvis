$paths = @(
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs",
    [System.Environment]::GetFolderPath('Programs'),
    [System.Environment]::GetFolderPath('Desktop'),
    [System.Environment]::GetFolderPath('CommonDesktop'),
    "$env:LOCALAPPDATA\Programs"
)

$apps = @()
foreach ($p in $paths) {
    if ($p -and (Test-Path $p)) {
        $files = Get-ChildItem -Path $p -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $apps += [PSCustomObject]@{
                name = $f.BaseName.ToLower()
                title = $f.BaseName
                path = $f.FullName
            }
        }
    }
}

$dest = Join-Path $PSScriptRoot "..\cache_apps.json"
$apps | ConvertTo-Json -Compress | Out-File -FilePath $dest -Encoding utf8
Write-Host "Indexed $($apps.Count) applications to cache_apps.json"
