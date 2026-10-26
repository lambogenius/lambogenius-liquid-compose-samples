<#
.SYNOPSIS
    Builds and runs the basics sample on http://localhost:7101, with Azurite and the GetCustomerName Function.

.DESCRIPTION
    Needs the .NET 8 SDK, Azure Functions Core Tools 4, Azurite, and the Compose using Liquid package in ../packages.
    Ctrl+C stops the Logic App and what this script started. Then, in another window: ./demo.ps1, or ./send.ps1.
#>
[CmdletBinding()]
param(
    [int]$Port = 7101,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Start-LiquidSample -App $PSScriptRoot -Port $Port -UsesFunction -Configuration $Configuration -Examples @(
    './send.ps1 order-to-sales-order'
    './send.ps1 xml-order-to-text'
)
