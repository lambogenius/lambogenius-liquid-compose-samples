<#
.SYNOPSIS
    Sends a customer update (JSON) to the update-customer workflow and prints the response.

.EXAMPLE
    ./send.ps1 messages/customer-update.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$File,

    [string]$BaseUrl = 'http://localhost:7106'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Write-LiquidResponse 'update-customer' $File (Invoke-LiquidWorkflow 'update-customer' $File -BaseUrl $BaseUrl)
