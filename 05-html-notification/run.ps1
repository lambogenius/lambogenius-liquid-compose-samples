<#
.SYNOPSIS
    Builds and runs the shipment-notification sample on http://localhost:7105, with Azurite and the stand-in mail
    API (backends/app.py, port 8105).

.DESCRIPTION
    Needs the .NET 8 SDK, Azure Functions Core Tools 4, Azurite, Python 3, and the Compose using Liquid package in
    ../packages. Ctrl+C stops the Logic App and what this script started. Then, in another window: ./demo.ps1, or
    ./send.ps1.
#>
[CmdletBinding()]
param(
    [int]$Port = 7105,
    [int]$BackendPort = 8105,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Start-LiquidSample -App $PSScriptRoot -Port $Port -BackendPort $BackendPort -Configuration $Configuration -Examples @(
    './send.ps1 messages/shipment-en.json     # then open the "preview" link in a browser'
)
