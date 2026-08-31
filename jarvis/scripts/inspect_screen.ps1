[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

try {
    $windows = Get-Process | Where-Object { $_.MainWindowTitle -and $_.MainWindowHandle -ne 0 } | Select-Object -Property Id, ProcessName, MainWindowTitle

    $lines = @()
    $lines += "=== ОТКРЫТЫЕ ОКНА НА ЭКРАНЕ ==="
    foreach ($w in $windows) {
        $lines += ("• [" + $w.ProcessName + "] " + $w.MainWindowTitle)
    }

    # Inspect active focused window and its UI controls/text
    $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
    if ($focused) {
        $lines += "`n=== АКТИВНОЕ ОКНО И ФОКУС ==="
        $lines += ("Активный заголовок: " + $focused.Current.Name)
        $lines += ("Тип элемента: " + $focused.Current.ControlType.ProgrammaticName)
        
        # Get child controls (buttons, text fields, document content)
        $condition = [System.Windows.Automation.Condition]::TrueCondition
        $children = $focused.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($children -and $children.Count -gt 0) {
            $uiTexts = @()
            foreach ($child in $children) {
                $name = $child.Current.Name
                if ($name -and $name.Trim().Length -gt 1 -and $name.Trim().Length -lt 200) {
                    $uiTexts += $name.Trim()
                }
            }
            if ($uiTexts.Count -gt 0) {
                $lines += "Элементы и текст на экране:"
                $lines += ($uiTexts | Select-Object -Unique | Select-Object -First 25 | ForEach-Object { "  - " + $_ })
            }
        }
    }

    Write-Output ($lines -join "`n")
} catch {
    Write-Output "Ошибка инспекции экрана: $_"
}
