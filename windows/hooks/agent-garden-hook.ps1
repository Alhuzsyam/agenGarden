# AgentGarden hook for Claude Code on Windows (PowerShell). Reports agent events
# to garden.exe and gates risky tools for phone/watch approval — the Windows
# counterpart of hooks/agent-garden-hook.sh.
#
# Wire it in Claude Code settings (%USERPROFILE%\.claude\settings.json), e.g.:
#   "hooks": {
#     "SessionStart": [{ "hooks": [{ "type": "command",
#        "command": "powershell -NoProfile -File \"%USERPROFILE%\\agentgarden\\agent-garden-hook.ps1\"" }] }],
#     "PreToolUse":  [{ "matcher": "*", "hooks": [{ "type": "command",
#        "command": "powershell -NoProfile -File \"%USERPROFILE%\\agentgarden\\agent-garden-hook.ps1\"" }] }],
#     "Stop":        [{ "hooks": [{ "type": "command",
#        "command": "powershell -NoProfile -File \"%USERPROFILE%\\agentgarden\\agent-garden-hook.ps1\"" }] }]
#   }
$ErrorActionPreference = 'SilentlyContinue'

$raw  = [Console]::In.ReadToEnd()
$data = try { $raw | ConvertFrom-Json } catch { $null }

$server    = if ($env:GARDEN_URL) { $env:GARDEN_URL } else { 'http://127.0.0.1:4141' }
$token     = (Get-Content (Join-Path $HOME '.agent-garden-token') -Raw).Trim()
$headers   = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
$agent     = Split-Path -Leaf (Get-Location).Path
$eventName = $data.hook_event_name

function Post($path, $body) {
    try { Invoke-RestMethod -Uri "$server$path" -Method Post -Headers $headers `
            -Body ($body | ConvertTo-Json -Compress) -TimeoutSec 5 | Out-Null } catch {}
}
function GetJson($path) {
    try { Invoke-RestMethod -Uri "$server$path" -Headers $headers -TimeoutSec 5 } catch { $null }
}

switch ($eventName) {
    'SessionStart' { Post '/event' @{ agent = $agent; event = 'start' } }
    'Stop'         { Post '/event' @{ agent = $agent; event = 'done' } }
    'PreToolUse' {
        $tool = $data.tool_name
        Post '/event' @{ agent = $agent; event = 'tool'; tool = $tool }

        $detail =
            if ($data.tool_input.command)    { [string]$data.tool_input.command }
            elseif ($data.tool_input.file_path) { "$tool $($data.tool_input.file_path)" }
            else { $tool }

        # Gate the tools that change things; read-only tools pass straight through.
        if ($tool -in @('Bash', 'Write', 'Edit', 'MultiEdit', 'NotebookEdit')) {
            $id = [guid]::NewGuid().ToString()
            Post '/approval/request' @{ id = $id; agent = $agent; tool = $tool; detail = $detail }
            $deadline = (Get-Date).AddSeconds(280)
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 800
                $r = GetJson "/approval/$id"
                if ($r.decision -eq 'allow') {
                    Post '/event' @{ agent = $agent; event = 'resume' }
                    exit 0
                }
                if ($r.decision -eq 'deny') {
                    @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'
                        permissionDecision = 'deny'
                        permissionDecisionReason = 'Ditolak dari HP/Garmin (AgentGarden)' } } |
                        ConvertTo-Json -Compress -Depth 5
                    exit 0
                }
            }
            # timed out with no answer -> fail open (allow)
        }
    }
}
exit 0
