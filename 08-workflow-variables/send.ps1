<#
.SYNOPSIS
    Calls one of the sample's workflows with a file and prints the response.

.EXAMPLE
    ./send.ps1 variables-as-parameters messages/order.json -Currency usd -TaxRate 0.05 -MaxLines 4 -Exclude GIFT-WRAP,CB-USB -Expedite
.EXAMPLE
    ./send.ps1 batch-loop messages/batch.json
.EXAMPLE
    ./send.ps1 dynamic-template messages/order.json -Format text
.EXAMPLE
    ./send.ps1 approval-routing messages/expense-gift.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('variables-as-parameters', 'batch-loop', 'dynamic-template', 'approval-routing')]
    [string]$Workflow,

    [Parameter(Mandatory, Position = 1)]
    [string]$File,

    # variables-as-parameters: sent as query parameters, and -Expedite as the x-expedite header.
    [string]$Currency,
    [int]$MaxLines,
    [string]$TaxRate,
    [string[]]$Exclude,
    [switch]$Expedite,

    # dynamic-template: json, csv or text.
    [string]$Format,

    [string]$BaseUrl = 'http://localhost:7108'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
$query = @(
    if ($Currency) { "currency=$([uri]::EscapeDataString($Currency))" }
    if ($MaxLines) { "maxLines=$MaxLines" }
    if ($TaxRate) { "taxRate=$([uri]::EscapeDataString($TaxRate))" }
    if ($Exclude) { "exclude=$([uri]::EscapeDataString($Exclude -join ','))" }
    if ($Format) { "format=$([uri]::EscapeDataString($Format))" }
) -join '&'
$headers = if ($Expedite) { @{ 'x-expedite' = 'true' } } else { @{} }
$response = Invoke-LiquidWorkflow $Workflow $File -BaseUrl $BaseUrl -Query $query -Headers $headers
Write-LiquidResponse $Workflow $File $response
foreach ($name in 'x-order-count', 'x-batch-total', 'x-skipped', 'x-template') {
    if ($response.Headers[$name]) { Write-Host "${name}: $($response.Headers[$name])" -ForegroundColor DarkGray }
}
