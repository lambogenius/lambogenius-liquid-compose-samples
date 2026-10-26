<#
.SYNOPSIS
    Calls one workflow of the running basics sample with its request in requests/ (or your own file) and prints the
    response.

.EXAMPLE
    ./send.ps1 order-to-sales-order
.EXAMPLE
    ./send.ps1 xml-order-to-text -File my-order.xml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('order-to-sales-order', 'plain-order-summary', 'order-to-text', 'xml-order-to-json', 'xml-order-to-text', 'inline-csharp-helpers')]
    [string]$Workflow,

    [string]$File,

    [string]$BaseUrl = 'http://localhost:7101'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
if (-not $File) { $File = Get-ChildItem (Join-Path $PSScriptRoot 'requests') -Filter "$Workflow.*" | Select-Object -First 1 -ExpandProperty FullName }
Write-LiquidResponse $Workflow $File (Invoke-LiquidWorkflow $Workflow $File -BaseUrl $BaseUrl)
