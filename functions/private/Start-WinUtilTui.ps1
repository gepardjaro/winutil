function Start-WinUtilTui {
    <#
    .SYNOPSIS
        Entry point for the WinUtil terminal UI. Renders a top-level menu and
        dispatches to the same Invoke-WPF* action functions the GUI uses.
        $PARAM_NOUI is force-true in TUI mode so Invoke-WPFUIThread's existing
        guard neutralises every taskbar / overlay / dispatcher call.
    #>

    while ($true) {
        Clear-Host
        Show-CTTLogo
        Write-Host ""
        Write-Host "  WinUtil $($sync.version) - Terminal UI" -ForegroundColor Cyan
        Write-Host "  --------------------------------------"
        Write-Host ""
        Write-Host "    1) Install"
        Write-Host "    2) Customize preferences"
        Write-Host "    3) Apply tweaks"
        Write-Host "    4) Undo tweaks"
        Write-Host "    5) Windows features"
        Write-Host "    6) DNS"
        Write-Host "    7) Performance plans"
        Write-Host "    q) Quit"
        Write-Host ""
        $choice = (Read-Host "  Select").ToString().Trim().ToLower()

        switch ($choice) {
            '1' { Invoke-WinUtilTuiInstallMenu }
            '2' { Invoke-WinUtilTuiPreferencesFlow }
            '3' { Invoke-WinUtilTuiTweaksFlow }
            '4' { Invoke-WinUtilTuiUndoFlow }
            '5' { Invoke-WinUtilTuiFeaturesFlow }
            '6' { Invoke-WinUtilTuiDnsFlow }
            '7' { Invoke-WinUtilTuiPerfPlansFlow }
            'q' { return }
            ''  { continue }
            default {
                Write-Host "  Unknown choice: '$choice'" -ForegroundColor Yellow
                Start-Sleep -Milliseconds 800
            }
        }
    }
}

function Invoke-WinUtilTuiInstallFlow {
    param([ValidateSet('Install','Uninstall')][string]$Action)

    $items = $sync.configs.applicationsHashtable.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{
            Key      = $_.Key
            Display  = $_.Value.content
            Category = $_.Value.category
            Selected = $false
        }
    }

    $title = if ($Action -eq 'Install') { 'Install applications' } else { 'Uninstall applications' }
    $result = Show-WinUtilTuiCheckboxList -Title $title -Items $items

    if (-not $result.Confirmed -or $result.SelectedKeys.Count -eq 0) { return }

    $sync.selectedApps.Clear()
    foreach ($key in $result.SelectedKeys) { $sync.selectedApps.Add($key) }

    Clear-Host
    Write-Host "  $Action queued for $($result.SelectedKeys.Count) app(s)..." -ForegroundColor Cyan
    Write-Host ""

    if ($Action -eq 'Install') {
        Invoke-WPFInstall
    } else {
        Invoke-WPFUnInstall
    }

    Wait-WinUtilTuiProcess
}

function Invoke-WinUtilTuiTweaksFlow {
    Clear-Host
    Write-Host "  Apply tweaks" -ForegroundColor Cyan
    Write-Host "  ---------------"
    Write-Host ""
    Write-Host "  Pick a preset to pre-select tweaks, or skip to choose individually:"
    Write-Host ""

    $presets = @($sync.configs.preset.PSObject.Properties.Name)
    for ($i = 0; $i -lt $presets.Count; $i++) {
        Write-Host "    $($i + 1)) $($presets[$i])"
    }
    Write-Host "    s) Skip presets, choose individually"
    Write-Host "    q) Cancel"
    Write-Host ""
    $choice = (Read-Host "  Select").ToString().Trim().ToLower()

    $preselected = @{}
    if ($choice -eq 'q' -or $choice -eq '') { return }
    if ($choice -ne 's') {
        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $presets.Count) {
            $presetName = $presets[$idx - 1]
            foreach ($k in $sync.configs.preset.$presetName) { $preselected[$k] = $true }
            Write-Host "  Preset '$presetName' loaded - review and adjust on the next screen." -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 800
        } else {
            return
        }
    }

    Write-Host "  Checking current system state..." -ForegroundColor DarkGray

    $items = $sync.configs.tweaks.PSObject.Properties | Where-Object {
        $_.Value.category -ne 'Customize Preferences'
    } | ForEach-Object {
        $isApplied = $false
        try {
            $r = @(Get-WinUtilToggleStatus -ToggleSwitch $_.Name 2>$null)
            $isApplied = [bool]($r | Select-Object -Last 1)
        } catch { $isApplied = $false }
        [pscustomobject]@{
            Key      = $_.Name
            Display  = $_.Value.Content
            Category = $_.Value.category
            Selected = $isApplied -or [bool]$preselected[$_.Name]
        }
    }

    $result = Show-WinUtilTuiCheckboxList -Title 'Apply tweaks' -Items $items

    if (-not $result.Confirmed -or $result.SelectedKeys.Count -eq 0) { return }

    $sync.selectedTweaks.Clear()
    foreach ($k in $result.SelectedKeys) { $sync.selectedTweaks.Add($k) }

    Clear-Host
    Write-Host "  Applying $($result.SelectedKeys.Count) tweak(s)..." -ForegroundColor Cyan
    Write-Host ""
    Invoke-WPFtweaksbutton
    Wait-WinUtilTuiProcess
}

function Invoke-WinUtilTuiUndoFlow {
    Clear-Host
    Write-Host "  Undo tweaks" -ForegroundColor Yellow
    Write-Host "  -----------"
    Write-Host ""
    Write-Host "  Checking current system state..." -ForegroundColor DarkGray

    $items = $sync.configs.tweaks.PSObject.Properties | Where-Object {
        $_.Value.category -ne 'Customize Preferences'
    } | ForEach-Object {
        $isApplied = $false
        try {
            $r = @(Get-WinUtilToggleStatus -ToggleSwitch $_.Name 2>$null)
            $isApplied = [bool]($r | Select-Object -Last 1)
        } catch { $isApplied = $false }
        [pscustomobject]@{
            Key      = $_.Name
            Display  = $_.Value.Content
            Category = $_.Value.category
            Selected = $isApplied
        }
    }

    $result = Show-WinUtilTuiCheckboxList -Title 'Undo tweaks' -Items $items
    if (-not $result.Confirmed -or $result.SelectedKeys.Count -eq 0) { return }

    $sync.selectedTweaks.Clear()
    foreach ($k in $result.SelectedKeys) { $sync.selectedTweaks.Add($k) }

    Clear-Host
    Write-Host "  Undoing $($result.SelectedKeys.Count) tweak(s)..." -ForegroundColor Cyan
    Write-Host ""
    Invoke-WPFundoall
    Wait-WinUtilTuiProcess
}

function Invoke-WinUtilTuiFeaturesFlow {
    $items = $sync.configs.feature.PSObject.Properties | Where-Object {
        $_.Value.category -eq 'Features'
    } | ForEach-Object {
        [pscustomobject]@{
            Key      = $_.Name
            Display  = $_.Value.Content
            Category = $_.Value.category
            Selected = $false
        }
    }

    if (-not $items -or $items.Count -eq 0) {
        Write-Host "  No installable features found in feature.json." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    $result = Show-WinUtilTuiCheckboxList -Title 'Windows features' -Items $items
    if (-not $result.Confirmed -or $result.SelectedKeys.Count -eq 0) { return }

    $sync.selectedFeatures.Clear()
    foreach ($k in $result.SelectedKeys) { $sync.selectedFeatures.Add($k) }

    Clear-Host
    Write-Host "  Installing $($result.SelectedKeys.Count) feature(s)..." -ForegroundColor Cyan
    Write-Host ""
    Invoke-WPFFeatureInstall
    Wait-WinUtilTuiProcess
}

function Invoke-WinUtilTuiPreferencesFlow {
    Write-Host "  Checking current preferences..." -ForegroundColor DarkGray

    $items = $sync.configs.tweaks.PSObject.Properties | Where-Object {
        $_.Value.category -eq 'Customize Preferences'
    } | ForEach-Object {
        $isApplied = $false
        try {
            $result = @(Get-WinUtilToggleStatus -ToggleSwitch $_.Name 2>$null)
            $isApplied = [bool]($result | Select-Object -Last 1)
        } catch { $isApplied = $false }
        [pscustomobject]@{
            Key      = $_.Name
            Display  = $_.Value.Content
            Category = $_.Value.category
            Selected = $isApplied
        }
    }

    if (-not $items -or $items.Count -eq 0) {
        Write-Host "  No preferences found." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    $result = Show-WinUtilTuiCheckboxList -Title 'Customize preferences' -Items $items
    if (-not $result.Confirmed) { return }

    $sync.selectedTweaks.Clear()
    foreach ($k in $result.SelectedKeys) { $sync.selectedTweaks.Add($k) }

    Clear-Host
    if ($result.SelectedKeys.Count -eq 0) {
        Write-Host "  No preferences selected — nothing to apply." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 1200
        return
    }
    Write-Host "  Applying $($result.SelectedKeys.Count) preference(s)..." -ForegroundColor Cyan
    Write-Host ""
    Invoke-WPFtweaksbutton
    Wait-WinUtilTuiProcess
}

function Invoke-WinUtilTuiInstallMenu {
    while ($true) {
        $pm = $sync.preferences.packagemanager
        Clear-Host
        Write-Host "  Install" -ForegroundColor Cyan
        Write-Host "  -------"
        Write-Host ""
        Write-Host "    1) Install applications"
        Write-Host "    2) Uninstall applications"
        Write-Host "    3) Upgrade all applications"
        Write-Host "    4) Show installed applications"
        Write-Host "    5) Package manager  (current: $pm)"
        Write-Host "    b) Back"
        Write-Host ""
        $choice = (Read-Host "  Select").ToString().Trim().ToLower()

        switch ($choice) {
            '1' { Invoke-WinUtilTuiInstallFlow -Action 'Install' }
            '2' { Invoke-WinUtilTuiInstallFlow -Action 'Uninstall' }
            '3' { Invoke-WinUtilTuiUpgradeFlow }
            '4' { Invoke-WinUtilTuiShowInstalledFlow }
            '5' { Invoke-WinUtilTuiPackageManagerFlow }
            'b' { return }
            ''  { continue }
            default {
                Write-Host "  Unknown choice: '$choice'" -ForegroundColor Yellow
                Start-Sleep -Milliseconds 800
            }
        }
    }
}

function Invoke-WinUtilTuiUpgradeFlow {
    Clear-Host
    Write-Host "  Upgrade all applications" -ForegroundColor Cyan
    Write-Host ""

    $useChoco = ($sync.preferences.packagemanager -eq [PackageManagers]::Choco)

    if ($useChoco) {
        Install-WinUtilChoco
        Write-Host "  Starting Chocolatey upgrade in a new window..." -ForegroundColor DarkGray
        Start-Process -FilePath powershell.exe -ArgumentList 'choco upgrade all -y'
    } else {
        Install-WinUtilWinget
        Write-Host "  Starting WinGet upgrade in a new window..." -ForegroundColor DarkGray
        Start-Process -FilePath powershell.exe -ArgumentList 'winget upgrade --all --include-unknown --silent --accept-source-agreements --accept-package-agreements'
    }

    Write-Host ""
    Write-Host "==========================================="
    Write-Host "--           Updates started            ---"
    Write-Host "-- You can close this window if desired ---"
    Write-Host "==========================================="
    Write-Host ""
    Write-Host "  Press any key to return to the menu..." -ForegroundColor Green
    [void][Console]::ReadKey($true)
}

function Invoke-WinUtilTuiShowInstalledFlow {
    Clear-Host
    Write-Host "  Scanning installed applications..." -ForegroundColor DarkGray

    $useChoco = ($sync.preferences.packagemanager -eq [PackageManagers]::Choco)
    $installedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($useChoco) {
        $chocoInstalled = (choco list | Select-String -Pattern '^\S+').Matches.Value
        foreach ($entry in $sync.configs.applicationsHashtable.GetEnumerator()) {
            $deps = @($entry.Value.choco -split ';')
            if ($deps | Where-Object { $chocoInstalled -contains $_ }) {
                [void]$installedSet.Add($entry.Key)
            }
        }
    } else {
        $origEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
        $installedPrograms = winget list -s winget 2>$null | Select-Object -Skip 3 |
            ConvertFrom-String -PropertyNames 'Name','Id','Version','Available' -Delimiter '\s{2,}'
        [Console]::OutputEncoding = $origEncoding

        foreach ($entry in $sync.configs.applicationsHashtable.GetEnumerator()) {
            $deps = @($entry.Value.winget -split ';')
            if ($deps[-1] -in $installedPrograms.Id) {
                [void]$installedSet.Add($entry.Key)
            }
        }
    }

    $items = $sync.configs.applicationsHashtable.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{
            Key      = $_.Key
            Display  = $_.Value.content
            Category = $_.Value.category
            Selected = $installedSet.Contains($_.Key)
        }
    }

    $found = $installedSet.Count
    if ($found -eq 0) {
        Write-Host "  No matching installed applications found in the WinUtil app list." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    $result = Show-WinUtilTuiCheckboxList -Title "Installed applications ($found found) — select to uninstall" -Items $items
    if (-not $result.Confirmed -or $result.SelectedKeys.Count -eq 0) { return }

    $sync.selectedApps.Clear()
    foreach ($key in $result.SelectedKeys) { $sync.selectedApps.Add($key) }

    Clear-Host
    Write-Host "  Uninstall queued for $($result.SelectedKeys.Count) app(s)..." -ForegroundColor Cyan
    Write-Host ""
    Invoke-WPFUnInstall
    Wait-WinUtilTuiProcess
}

function Invoke-WinUtilTuiPackageManagerFlow {
    Clear-Host
    Write-Host "  Package manager" -ForegroundColor Cyan
    Write-Host "  ---------------"
    Write-Host ""
    $current = $sync.preferences.packagemanager
    Write-Host "  Current: $current" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    1) Winget$(if ($current -eq [PackageManagers]::Winget) { '  [active]' })"
    Write-Host "    2) Chocolatey$(if ($current -eq [PackageManagers]::Choco) { '  [active]' })"
    Write-Host "    b) Back"
    Write-Host ""
    $choice = (Read-Host "  Select").ToString().Trim().ToLower()

    switch ($choice) {
        '1' {
            $sync.preferences.packagemanager = [PackageManagers]::Winget
            Set-Preferences -save
            Write-Host "  Package manager set to Winget." -ForegroundColor Green
            Start-Sleep -Milliseconds 800
        }
        '2' {
            $sync.preferences.packagemanager = [PackageManagers]::Choco
            Set-Preferences -save
            Write-Host "  Package manager set to Chocolatey." -ForegroundColor Green
            Start-Sleep -Milliseconds 800
        }
        'b' { return }
        default {
            Write-Host "  Unknown choice: '$choice'" -ForegroundColor Yellow
            Start-Sleep -Milliseconds 800
        }
    }
}

function Invoke-WinUtilTuiDnsFlow {
    Clear-Host
    Write-Host "  DNS - Set to" -ForegroundColor Cyan
    Write-Host "  ------------"
    Write-Host ""

    $providers = @('Default (DHCP)') + @($sync.configs.dns.PSObject.Properties.Name)
    for ($i = 0; $i -lt $providers.Count; $i++) {
        Write-Host "    $($i + 1)) $($providers[$i])"
    }
    Write-Host "    b) Back"
    Write-Host ""
    $choice = (Read-Host "  Select").ToString().Trim().ToLower()

    if ($choice -eq 'b' -or $choice -eq '') { return }

    $idx = 0
    if (-not ([int]::TryParse($choice, [ref]$idx)) -or $idx -lt 1 -or $idx -gt $providers.Count) {
        Write-Host "  Unknown choice: '$choice'" -ForegroundColor Yellow
        Start-Sleep -Milliseconds 800
        return
    }

    $chosen = $providers[$idx - 1]
    $dnsKey = if ($chosen -eq 'Default (DHCP)') { 'DHCP' } else { $chosen }

    Write-Host ""
    Write-Host "  Applying DNS: $chosen ..." -ForegroundColor DarkGray
    Set-WinUtilDNS -DNSProvider $dnsKey
    Write-Host ""
    Write-Host "  DNS set to $chosen." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Invoke-WinUtilTuiPerfPlansFlow {
    Clear-Host
    Write-Host "  Performance plans" -ForegroundColor Cyan
    Write-Host "  -----------------"
    Write-Host ""
    Write-Host "    1) Enable Ultimate Performance profile"
    Write-Host "    2) Disable Ultimate Performance profile"
    Write-Host "    b) Back"
    Write-Host ""
    $choice = (Read-Host "  Select").ToString().Trim().ToLower()

    switch ($choice) {
        '1' {
            Write-Host ""
            Invoke-WPFUltimatePerformance -Do
            Write-Host ""
            Write-Host "  Done. Press any key to return..." -ForegroundColor Green
            [void][Console]::ReadKey($true)
        }
        '2' {
            Write-Host ""
            Invoke-WPFUltimatePerformance
            Write-Host ""
            Write-Host "  Done. Press any key to return..." -ForegroundColor Green
            [void][Console]::ReadKey($true)
        }
        'b' { return }
        default {
            Write-Host "  Unknown choice: '$choice'" -ForegroundColor Yellow
            Start-Sleep -Milliseconds 800
        }
    }
}

function Wait-WinUtilTuiProcess {
    <#
    .SYNOPSIS
        Blocks the TUI main thread until the background action runspace clears
        $sync.ProcessRunning. Log output from the action flows to Write-Host in
        the background and appears in real time in the same console.
    #>
    # The runspace sets ProcessRunning=true asynchronously after BeginInvoke().
    # Wait up to 3s for it to start before polling for completion.
    $elapsed = 0
    while (-not $sync.ProcessRunning -and $elapsed -lt 3000) {
        Start-Sleep -Milliseconds 100
        $elapsed += 100
    }
    while ($sync.ProcessRunning) {
        Start-Sleep -Milliseconds 500
    }
    Write-Host ""
    Write-Host "  Done. Press any key to return to the menu..." -ForegroundColor Green
    [void][Console]::ReadKey($true)
}
