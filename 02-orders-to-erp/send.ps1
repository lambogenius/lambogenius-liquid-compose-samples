<#
.SYNOPSIS
    Sends an order file to one of the sample's workflows and prints the response.

.EXAMPLE
    ./send.ps1 webshop-order messages/webshop-order.json
.EXAMPLE
    ./send.ps1 partner-order messages/partner-po.xml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('webshop-order', 'partner-order')]
    [string]$Workflow,

    [Parameter(Mandatory, Position = 1)]
    [string]$File,

    [string]$BaseUrl = 'http://localhost:7102'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Write-LiquidResponse $Workflow $File (Invoke-LiquidWorkflow $Workflow $File -BaseUrl $BaseUrl)
