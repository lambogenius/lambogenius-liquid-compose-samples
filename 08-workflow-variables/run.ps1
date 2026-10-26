<#
.SYNOPSIS
    Builds and runs the workflow variables sample on http://localhost:7108, with Azurite.

.DESCRIPTION
    Needs the .NET 8 SDK, Azure Functions Core Tools 4, Azurite, and the Compose using Liquid package in ../packages.
    Ctrl+C stops the Logic App and what this script started. Then, in another window: ./demo.ps1, or ./send.ps1.
#>
[CmdletBinding()]
param(
    [int]$Port = 7108,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Start-LiquidSample -App $PSScriptRoot -Port $Port -Configuration $Configuration -Examples @(
    './send.ps1 variables-as-parameters messages/order.json -MaxLines 4 -Exclude GIFT-WRAP -Expedite'
    './send.ps1 batch-loop messages/batch.json'
    './send.ps1 dynamic-template messages/order.json -Format csv'
    './send.ps1 approval-routing messages/expense-travel.json'
)
