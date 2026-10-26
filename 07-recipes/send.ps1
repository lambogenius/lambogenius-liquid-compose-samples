<#
.SYNOPSIS
    Calls one recipe workflow with a file and prints the response.

.EXAMPLE
    ./send.ps1 xpath messages/shipment.xml
.EXAMPLE
    ./send.ps1 parameters messages/order.json -Tenant contoso -Mode test
.EXAMPLE
    ./send.ps1 error-handling messages/error-case.json -Case template-missing
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('liquid-essentials', 'parameters', 'partials', 'template-versions', 'xpath', 'tojson', 'error-handling')]
    [string]$Workflow,

    [Parameter(Mandatory, Position = 1)]
    [string]$File,

    # error-handling: which template in Artifacts/LiquidTemplates/errors to run.
    [ValidateSet('template-missing', 'invalid-json-output', 'syntax-error', 'unknown-filter', 'scripts-disabled', 'helper-throws', 'slow-helper', 'function-not-allowed', 'unknown-customer')]
    [string]$Case,

    # parameters: sent as the x-tenant header and the mode query parameter.
    [string]$Tenant,
    [string]$Mode,

    [string]$BaseUrl = 'http://localhost:7107'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
$query = @(
    if ($Case) { "case=$Case" }
    if ($Mode) { "mode=$([uri]::EscapeDataString($Mode))" }
) -join '&'
$headers = if ($Tenant) { @{ 'x-tenant' = $Tenant } } else { @{} }
Write-LiquidResponse $Workflow $File (Invoke-LiquidWorkflow $Workflow $File -BaseUrl $BaseUrl -Query $query -Headers $headers)
