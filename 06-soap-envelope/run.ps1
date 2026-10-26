<#
.SYNOPSIS
    Builds and runs the SOAP sample on http://localhost:7106, with Azurite and the stand-in legacy CRM
    (backends/app.py, port 8106).

.DESCRIPTION
    Needs the .NET 8 SDK, Azure Functions Core Tools 4, Azurite, Python 3, and the Compose using Liquid package in
    ../packages. Ctrl+C stops the Logic App and what this script started. Then, in another window: ./demo.ps1, or
    ./send.ps1.
#>
[CmdletBinding()]
param(
    [int]$Port = 7106,
    [int]$BackendPort = 8106,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Start-LiquidSample -App $PSScriptRoot -Port $Port -BackendPort $BackendPort -Configuration $Configuration -Examples @(
    './send.ps1 messages/customer-update.json'
)
