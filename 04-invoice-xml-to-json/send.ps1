<#
.SYNOPSIS
    Sends a UBL invoice to the supplier-invoice workflow and prints the response.

.EXAMPLE
    ./send.ps1 messages/invoice.xml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$File,

    [string]$BaseUrl = 'http://localhost:7104'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Write-LiquidResponse 'supplier-invoice' $File (Invoke-LiquidWorkflow 'supplier-invoice' $File -BaseUrl $BaseUrl)
