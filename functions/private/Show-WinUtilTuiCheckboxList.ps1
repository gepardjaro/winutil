function Show-WinUtilTuiCheckboxList {
    <#
    .SYNOPSIS
        Renders an interactive multi-select checkbox list in the terminal.
        Used by the Terminal UI to pick apps / tweaks / features without WPF.
    .PARAMETER Title
        Header text shown above the list.
    .PARAMETER Items
        Array of objects with Key, Display, Category, Selected properties.
    .OUTPUTS
        [pscustomobject]@{ Confirmed = $true/$false; SelectedKeys = @(...) }
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$Items
    )

    if (-not $Items -or $Items.Count -eq 0) {
        Write-Host "  (No items to show.)" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return [pscustomobject]@{ Confirmed = $false; SelectedKeys = @() }
    }

    $sorted = @($Items | Sort-Object Category, Display)
    $selected = @{}
    foreach ($it in $sorted) { $selected[$it.Key] = [bool]$it.Selected }

    $filter = ''
    $cursor = 0
    $viewTop = 0

    while ($true) {
        $visible = if ($filter) {
            @($sorted | Where-Object {
                $_.Display -like "*$filter*" -or
                $_.Category -like "*$filter*" -or
                $_.Key -like "*$filter*"
            })
        } else {
            @($sorted)
        }

        if ($visible.Count -eq 0) {
            $cursor = 0
        } elseif ($cursor -ge $visible.Count) {
            $cursor = $visible.Count - 1
        } elseif ($cursor -lt 0) {
            $cursor = 0
        }

        $viewportH = [Math]::Max(5, [Console]::WindowHeight - 7)
        if ($cursor -lt $viewTop) { $viewTop = $cursor }
        if ($cursor -ge $viewTop + $viewportH) { $viewTop = $cursor - $viewportH + 1 }
        if ($viewTop -lt 0) { $viewTop = 0 }

        Clear-Host
        Write-Host "  $Title" -ForegroundColor Cyan
        $countSel = @($selected.GetEnumerator() | Where-Object { $_.Value }).Count
        $filterMsg = if ($filter) { "  filter='$filter'" } else { '' }
        Write-Host ("  Selected {0} / {1}{2}" -f $countSel, $sorted.Count, $filterMsg) -ForegroundColor DarkGray
        Write-Host ""

        if ($visible.Count -eq 0) {
            Write-Host "    (No items match filter)" -ForegroundColor Yellow
        } else {
            $end = [Math]::Min($visible.Count, $viewTop + $viewportH)
            for ($i = $viewTop; $i -lt $end; $i++) {
                $it = $visible[$i]
                $mark = if ($selected[$it.Key]) { '[x]' } else { '[ ]' }
                $line = if ($it.Category) { "$mark $($it.Category) > $($it.Display)" } else { "$mark $($it.Display)" }
                if ($i -eq $cursor) {
                    Write-Host "  > $line" -ForegroundColor Yellow
                } else {
                    Write-Host "    $line"
                }
            }
        }

        Write-Host ""
        Write-Host "  arrows move | space toggle | / filter | a all | c clear | enter confirm | esc cancel" -ForegroundColor DarkGray

        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            'UpArrow'   { if ($cursor -gt 0) { $cursor-- } }
            'DownArrow' { if ($cursor -lt $visible.Count - 1) { $cursor++ } }
            'PageUp'    { $cursor = [Math]::Max(0, $cursor - 10) }
            'PageDown'  { $cursor = [Math]::Min($visible.Count - 1, $cursor + 10) }
            'Home'      { $cursor = 0 }
            'End'       { $cursor = $visible.Count - 1 }
            'Spacebar'  {
                if ($visible.Count -gt 0) {
                    $key2 = $visible[$cursor].Key
                    $selected[$key2] = -not $selected[$key2]
                }
            }
            'Enter'     {
                return [pscustomobject]@{
                    Confirmed = $true
                    SelectedKeys = @($selected.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key })
                }
            }
            'Escape'    { return [pscustomobject]@{ Confirmed = $false; SelectedKeys = @() } }
            'Oem2'      {
                Write-Host ""
                $filter = Read-Host "  Filter (empty = clear)"
                $cursor = 0; $viewTop = 0
            }
            default {
                switch -CaseSensitive ([string]$k.KeyChar) {
                    '/' {
                        Write-Host ""
                        $filter = Read-Host "  Filter (empty = clear)"
                        $cursor = 0; $viewTop = 0
                    }
                    { $_ -eq 'a' -or $_ -eq 'A' } {
                        foreach ($it in $visible) { $selected[$it.Key] = $true }
                    }
                    { $_ -eq 'c' -or $_ -eq 'C' } {
                        foreach ($k2 in @($selected.Keys)) { $selected[$k2] = $false }
                    }
                    { $_ -eq 'q' -or $_ -eq 'Q' } {
                        return [pscustomobject]@{ Confirmed = $false; SelectedKeys = @() }
                    }
                }
            }
        }
    }
}
