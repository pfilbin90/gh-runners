<#
.SYNOPSIS
    Updates Claude Code and Gemini CLI on the local Windows machine.

.DESCRIPTION
    Run every 6 hours via Windows Task Scheduler to keep tools up to date.
#>

$ErrorActionPreference = "Stop"

$logFile = Join-Path $PSScriptRoot "claude-code-local-update.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log {
    param([string]$Message)
    $entry = "[$timestamp] $Message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

Write-Log "Starting local CLI updates..."

try {
    Write-Log "Updating Claude Code..."
    $output = npm update -g @anthropic-ai/claude-code 2>&1
    Write-Log "npm output: $output"

    $version = claude --version 2>&1
    Write-Log "Claude Code version: $version"
} catch {
    Write-Log "ERROR updating Claude Code: $_"
}

try {
    Write-Log "Updating Gemini CLI..."
    $output = npm update -g @google/gemini-cli 2>&1
    Write-Log "npm output: $output"

    $version = gemini --version 2>&1
    Write-Log "Gemini CLI version: $version"
} catch {
    Write-Log "ERROR updating Gemini CLI: $_"
}

Write-Log "Local CLI updates completed."
