<#
.SYNOPSIS
    Sends a JSON file to one of the sample's workflows and prints the file it returns, or saves it with -OutFile.

.EXAMPLE
    ./send.ps1 orders-to-csv messages/orders.json -OutFile orders.csv
.EXAMPLE
    ./send.ps1 payments-to-bank-file messages/payments.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('orders-to-csv', 'payments-to-bank-file')]
    [string]$Workflow,

    [Parameter(Mandatory, Position = 1)]
    [string]$File,

    [string]$OutFile,

    [string]$BaseUrl = 'http://localhost:7103'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
$response = Invoke-LiquidWorkflow $Workflow $File -BaseUrl $BaseUrl
if ($OutFile -and $response.Status -eq 200) {
    # Written as received: UTF-8 without a BOM, CRLF line endings.
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $OutFile), $response.Text, [System.Text.UTF8Encoding]::new($false))
    Write-Host "HTTP 200: saved $OutFile ($($response.Headers['Content-Disposition']))" -ForegroundColor Green
}
else {
    Write-LiquidResponse $Workflow $File $response
}
