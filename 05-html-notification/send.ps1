<#
.SYNOPSIS
    Sends a shipment event to the shipment-notification workflow and prints the response. Open its "preview" link
    in a browser to see the email.

.EXAMPLE
    ./send.ps1 messages/shipment-fr.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$File,

    [string]$BaseUrl = 'http://localhost:7105'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Write-LiquidResponse 'shipment-notification' $File (Invoke-LiquidWorkflow 'shipment-notification' $File -BaseUrl $BaseUrl)
