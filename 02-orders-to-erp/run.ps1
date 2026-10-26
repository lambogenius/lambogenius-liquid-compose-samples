<#
.SYNOPSIS
    Builds and runs the orders-to-ERP sample on http://localhost:7102, with Azurite, the GetCustomerName Function and
    the stand-in ERP and warehouse (backends/app.py, port 8102).

.DESCRIPTION
    Needs the .NET 8 SDK, Azure Functions Core Tools 4, Azurite, Python 3, and the Compose using Liquid package in
    ../packages. Ctrl+C stops the Logic App and what this script started. Then, in another window: ./demo.ps1, or
    ./send.ps1.
#>
[CmdletBinding()]
param(
    [int]$Port = 7102,
    [int]$BackendPort = 8102,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Start-LiquidSample -App $PSScriptRoot -Port $Port -UsesFunction -BackendPort $BackendPort -Configuration $Configuration -Examples @(
    './send.ps1 webshop-order messages/webshop-order.json'
    './send.ps1 partner-order messages/partner-po.xml'
)
