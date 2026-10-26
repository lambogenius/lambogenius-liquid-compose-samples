<#
.SYNOPSIS
    Builds and runs the CSV and bank-file export sample on http://localhost:7103, with Azurite.

.DESCRIPTION
    Needs the .NET 8 SDK, Azure Functions Core Tools 4, Azurite, and the Compose using Liquid package in ../packages.
    Ctrl+C stops the Logic App and what this script started. Then, in another window: ./demo.ps1, or ./send.ps1.
#>
[CmdletBinding()]
param(
    [int]$Port = 7103,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Start-LiquidSample -App $PSScriptRoot -Port $Port -Configuration $Configuration -Examples @(
    './send.ps1 orders-to-csv messages/orders.json -OutFile orders.csv'
    './send.ps1 payments-to-bank-file messages/payments.json'
)
