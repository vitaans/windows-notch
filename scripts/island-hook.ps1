# Copyright (C) 2026 the windows-notch authors. Licensed GPL-3.0-or-later, see LICENSE.
# Windows Notch - hook script (lives in <island folder>\scripts, writes to <island folder>\state)
# Claude Code runs this on UserPromptSubmit, PreToolUse, Notification, Stop and SessionEnd.
# It reads the hook JSON from stdin and writes a tiny per-session status file
# that the overlay (ClaudeIsland.ps1) picks up. It must never print anything:
# stdout from some hooks is added to Claude's context.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $d = $raw | ConvertFrom-Json
    $sid = [string]$d.session_id
    if (-not $sid) { exit 0 }

    $root = Split-Path $PSScriptRoot -Parent
    $dir = Join-Path $root 'state\sessions'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $file = Join-Path $dir ($sid + '.json')
    $now  = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $ev   = [string]$d.hook_event_name

    if ($ev -eq 'SessionEnd') {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # Load previous state for this session (if any)
    $st = @{ id = $sid; state = 'idle'; label = ''; project = ''; message = ''; started = $now; updated = $now; finished = 0 }
    if (Test-Path -LiteralPath $file) {
        try {
            $prev = [IO.File]::ReadAllText($file) | ConvertFrom-Json
            foreach ($p in $prev.PSObject.Properties) { $st[$p.Name] = $p.Value }
        } catch { }
    }
    if ($d.cwd) { $st.project = Split-Path ([string]$d.cwd) -Leaf }

    function Get-ToolLabel($tool, $inp) {
        $leaf = ''
        if ($inp -and $inp.file_path) { $leaf = Split-Path ([string]$inp.file_path) -Leaf }
        switch -Regex ($tool) {
            '^(Edit|MultiEdit)$' { if ($leaf) { return "Editing $leaf" } else { return 'Editing' } }
            '^Write$'            { if ($leaf) { return "Writing $leaf" } else { return 'Writing' } }
            '^Read$'             { if ($leaf) { return "Reading $leaf" } else { return 'Reading' } }
            '^NotebookEdit$'     { return 'Editing notebook' }
            '^Bash$'             { return 'Running command' }
            '^PowerShell$'       { return 'Running command' }
            '^(Grep|Glob|LS)$'   { return 'Searching' }
            '^(WebFetch|WebSearch)$' { return 'Browsing the web' }
            '^(Task|Agent)$'     { return 'Running an agent' }
            '^(TodoWrite|TaskCreate|TaskUpdate)$' { return 'Planning' }
            '^mcp__([^_]+(?:_[^_]+)*)__' { return 'Using ' + ($Matches[1] -replace '[_-]', ' ') }
            default              { if ($tool) { return [string]$tool } else { return '' } }
        }
    }

    switch ($ev) {
        'UserPromptSubmit' {
            $st.state = 'working'; $st.label = ''; $st.message = ''
            $st.started = $now; $st.finished = 0
        }
        'PreToolUse' {
            # A tool call after a finished turn means a new run started without a prompt
            if ([int64]$st.finished -gt 0) { $st.started = $now; $st.finished = 0 }
            $st.state = 'working'
            $st.message = ''
            $st.label = Get-ToolLabel ([string]$d.tool_name) $d.tool_input
        }
        'Notification' {
            $msg  = [string]$d.message
            $kind = [string]$d.notification_type
            # Ignore the "Claude is waiting for your input" reminder that fires after a task is done
            if ($kind -eq 'idle_prompt' -or $msg -match 'waiting for your input') { exit 0 }
            $st.state = 'needs'; $st.message = $msg
        }
        'Stop' {
            $st.state = 'done'; $st.finished = $now; $st.message = ''
            # Model + session token count from the transcript (deduped per message id)
            $tp = [string]$d.transcript_path
            if ($tp -and (Test-Path -LiteralPath $tp)) {
                try {
                    $tok = [int64]0; $model = ''; $cost = [double]0
                    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
                    # Price table (USD per million tokens), longest id first so prefixes match correctly
                    $prices = @()
                    $pf = Join-Path $root 'data\agent-prices.json'
                    if (Test-Path -LiteralPath $pf) {
                        try { $prices = @((Get-Content -LiteralPath $pf -Raw | ConvertFrom-Json).claude.models | Sort-Object { $_.id.Length } -Descending) } catch { }
                    }
                    function Get-Num($ln, $key) {
                        $m = [regex]::Match($ln, '"' + $key + '"\s*:\s*(\d+)')
                        if ($m.Success) { return [int64]$m.Groups[1].Value } else { return [int64]0 }
                    }
                    $fs = New-Object System.IO.FileStream($tp, 'Open', 'Read', 'ReadWrite')
                    $sr = New-Object System.IO.StreamReader($fs)
                    while ($null -ne ($line = $sr.ReadLine())) {
                        if ($line.IndexOf('"usage"') -lt 0) { continue }
                        $idm = [regex]::Match($line, '"id"\s*:\s*"(msg_[^"]+)"')
                        if ($idm.Success -and -not $seen.Add($idm.Groups[1].Value)) { continue }
                        $mm = [regex]::Match($line, '"model"\s*:\s*"(claude-[^"]+)"')
                        $msgModel = if ($mm.Success) { $mm.Groups[1].Value } else { '' }
                        if ($msgModel) { $model = $msgModel }
                        $in  = Get-Num $line 'input_tokens'
                        $out = Get-Num $line 'output_tokens'
                        $cw  = Get-Num $line 'cache_creation_input_tokens'
                        $cr  = Get-Num $line 'cache_read_input_tokens'
                        $cw1 = Get-Num $line 'ephemeral_1h_input_tokens'
                        $tok += $in + $out + $cw
                        # API value, the way Vorssaint estimates it
                        if ($msgModel -and $prices.Count) {
                            $p = $prices | Where-Object { $msgModel.StartsWith([string]$_.id) } | Select-Object -First 1
                            if ($p) {
                                $long = if ($p.cacheWriteLong) { [double]$p.cacheWriteLong } else { [double]$p.cacheWrite }
                                $cost += ($in * [double]$p.input + $out * [double]$p.output + $cr * [double]$p.cacheRead +
                                          ($cw - $cw1) * [double]$p.cacheWrite + $cw1 * $long) / 1000000
                            }
                        }
                    }
                    $sr.Close(); $fs.Close()
                    $st.tokens = $tok
                    if ($cost -gt 0) { $st.cost = [math]::Round($cost, 4) }
                    if ($model) {
                        # claude-sonnet-4-5-20250929 -> Sonnet 4.5
                        $parts = @(($model -replace '^claude-', '') -split '-' | Where-Object { $_ -notmatch '^\d{8}$' })
                        $name = @($parts | Where-Object { $_ -notmatch '^\d+$' }) -join ' '
                        $ver  = @($parts | Where-Object { $_ -match '^\d+$' }) -join '.'
                        if ($name) { $name = $name.Substring(0, 1).ToUpper() + $name.Substring(1) }
                        $st.model = ("$name $ver").Trim()
                    }
                } catch { }
            }
        }
        default { exit 0 }
    }
    $st.updated = $now

    # Atomic write so the overlay never reads half a file
    $tmp = Join-Path $dir ($sid + '.tmp')
    [IO.File]::WriteAllText($tmp, ($st | ConvertTo-Json -Compress))
    Move-Item -LiteralPath $tmp -Destination $file -Force
} catch { }
exit 0
