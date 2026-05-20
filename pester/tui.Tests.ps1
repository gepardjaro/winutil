# Guards that catch upstream PRs which would silently break the TUI flow.
# The TUI delegates to the same Invoke-WPF* action functions the GUI uses, so
# the breakage modes are limited:
#   1) A new function in functions/public/ reaches into $sync.Form directly
#      (outside an Invoke-WPFUIThread block) - this would NRE in TUI mode.
#   2) Set-WinUtilProgressbar or similar is called without its existing
#      $PARAM_NOUI guard.
#   3) A new Invoke-WPFButton case adds direct $sync.Form access that the TUI
#      cannot route around.
# Each check has an explicit allowlist of cases known to be GUI-chrome-only.

Describe "TUI safety guards" {

    BeforeAll {
        $script:repoRoot       = Resolve-Path (Join-Path $PSScriptRoot '..')
        $script:publicDir      = Join-Path $repoRoot 'functions/public'
        $script:privateDir     = Join-Path $repoRoot 'functions/private'
        $script:invokeButton   = Join-Path $publicDir 'Invoke-WPFButton.ps1'

        # Functions whose direct $sync.Form access is intentional GUI chrome.
        # These are never called from the TUI dispatcher, so they're safe.
        # When upstream adds a new entry here, treat it as a conscious "TUI does
        # not need to support this" review gate.
        $script:guiChromeFunctions = @(
            'Invoke-WPFButton',           # close/minimize/FOSS-highlight cases
            'Invoke-WPFPopup',            # popup visibility
            'Invoke-WPFTab',              # tab switching
            'Invoke-WPFUIElements',       # dynamic UI build
            'Invoke-WPFUIThread',         # the dispatcher itself
            'Initialize-WPFUI',           # dynamic UI init
            'Invoke-WPFGetInstalled'      # populates GUI checkboxes from system state
        )
    }

    Context "Public action functions" {
        It "do not access `$sync.Form outside Invoke-WPFUIThread (excluding GUI-chrome list)" {
            $offenders = New-Object System.Collections.Generic.List[string]
            Get-ChildItem -Path $publicDir -Filter *.ps1 | ForEach-Object {
                $fnName = $_.BaseName
                if ($guiChromeFunctions -contains $fnName) { return }

                $content = Get-Content $_.FullName -Raw
                # Strip everything inside Invoke-WPFUIThread -ScriptBlock { ... } blocks
                # so direct $sync.Form references outside those blocks are flagged.
                $stripped = [regex]::Replace($content, 'Invoke-WPFUIThread\s+-ScriptBlock\s*\{[^{}]*(\{[^{}]*\}[^{}]*)*\}', '', 'Singleline')
                if ($stripped -match '\$sync\.Form\b' -or $stripped -match '\$sync\["Form"\]') {
                    $offenders.Add($fnName)
                }
            }
            $offenders -join ', ' | Should -BeNullOrEmpty
        }
    }

    Context "TUI dispatcher targets" {
        It "every Invoke-WPF* function the TUI calls exists in functions/public/" {
            $tuiTargets = @(
                'Invoke-WPFInstall',
                'Invoke-WPFUnInstall',
                'Invoke-WPFtweaksbutton',
                'Invoke-WPFundoall',
                'Invoke-WPFFeatureInstall'
            )
            $missing = $tuiTargets | Where-Object {
                -not (Test-Path (Join-Path $publicDir "$_.ps1"))
            }
            $missing -join ', ' | Should -BeNullOrEmpty
        }
    }

    Context "Sync hashtable selection contract" {
        It "the keys the TUI populates are still referenced by their action functions" {
            $contracts = @{
                '$sync.selectedApps'     = 'Invoke-WPFInstall.ps1'
                '$sync.selectedTweaks'   = 'Invoke-WPFtweaksbutton.ps1'
                '$sync.selectedFeatures' = 'Invoke-WPFFeatureInstall.ps1'
            }
            $broken = @()
            foreach ($prop in $contracts.Keys) {
                $file = Join-Path $publicDir $contracts[$prop]
                if (-not (Test-Path $file)) { $broken += "missing:$($contracts[$prop])"; continue }
                $literal = [regex]::Escape($prop)
                if ((Get-Content $file -Raw) -notmatch $literal) {
                    $broken += "$prop not read by $($contracts[$prop])"
                }
            }
            $broken -join '; ' | Should -BeNullOrEmpty
        }
    }

    Context "TUI module surface" {
        It "the entry function Start-WinUtilTui exists" {
            Test-Path (Join-Path $privateDir 'Start-WinUtilTui.ps1') | Should -BeTrue
        }
        It "the checkbox renderer exists" {
            Test-Path (Join-Path $privateDir 'Show-WinUtilTuiCheckboxList.ps1') | Should -BeTrue
        }
        It "every TUI private function follows the WinUtil/WPF naming convention" {
            Get-ChildItem -Path $privateDir -Filter '*Tui*.ps1' | ForEach-Object {
                $_.BaseName | Should -Match '(?i)winutil|wpf'
            }
        }
    }
}
