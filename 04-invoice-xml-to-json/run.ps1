<#
.SYNOPSIS
    Builds and runs the supplier-invoice sample on http://localhost:7104, with Azurite and the stand-in accounts
    payable API (backends/app.py, port 8104).

.DESCRIPTION
    Needs the .NET 8 SDK, Azure Functions Core Tools 4, Azurite, Python 3, and the Compose using Liquid package in
    ../packages. Ctrl+C stops the Logic App and what this script started. Then, in another window: ./demo.ps1, or
    ./send.ps1.
#>
[CmdletBinding()]
param(
    [int]$Port = 7104,
    [int]$BackendPort = 8104,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Start-LiquidSample -App $PSScriptRoot -Port $Port -BackendPort $BackendPort -Configuration $Configuration -Examples @(
    './send.ps1 messages/invoice.xml'
)
