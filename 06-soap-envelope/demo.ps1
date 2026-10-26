<#
.SYNOPSIS
    Sends the customer updates in messages/ and checks the SOAP requests the stand-in CRM received and the JSON the
    caller got back. Start the sample first with ./run.ps1. Exits with 1 when a check fails.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:7106',
    [string]$BackendUrl = 'http://127.0.0.1:8106'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Set-Location $PSScriptRoot

function Send([string]$file) {
    $r = Invoke-LiquidWorkflow 'update-customer' $file -BaseUrl $BaseUrl
    Write-Host "  POST update-customer $(Split-Path $file -Leaf) -> HTTP $($r.Status)"
    $r
}

function Received { Invoke-RestMethod "$BackendUrl/received" }
function Control([string]$what) { Invoke-RestMethod -Method Post "$BackendUrl/control/$what" | Out-Null }

try { Control 'reset' } catch { throw "The stand-in CRM is not answering on $BackendUrl. Start the sample with ./run.ps1 first." }

Step '1. A customer update (JSON) becomes a SOAP 1.1 request; the SOAP response comes back as JSON.'
$r = Send 'messages/customer-update.json'
Check 'HTTP 200 with the new version from the SOAP response' ($r.Status -eq 200 -and $r.Body.ok -eq $true -and $r.Body.customerId -eq 'C300' -and $r.Body.version -eq 8 -and @($r.Body.warnings).Count -eq 0) "($($r.Status) $($r.Text))"
$update = (Received).updates[-1]
Check 'the CRM parsed the envelope: quotes, <, > and & in the name survived' ($update.name -eq 'Initech "Québec" <Ltée> & Co' -and $update.city -eq 'Montréal') "($($update.name))"
Check 'C# helpers: phone in E.164, credit limit as xs:decimal' ($update.phone -eq '+15145550199' -and $update.creditLimit -eq '25000.00' -and $update.active -eq 'true')
Check 'both address lines, and the application id in the SOAP header' ($update.lines.Count -eq 2 -and $update.lines[1] -eq 'Bureau 4100' -and $update.applicationId -eq 'logicapp-crm-sync')
Show ($update.xml -replace '(?s)<soap:Header>.*</soap:Header>', '<soap:Header>...</soap:Header>')

Step '2. A customer without a phone number: the CRM accepts it with a warning.'
$r = Send 'messages/customer-no-phone.json'
Check 'HTTP 200 with the warning as an array (XmlValues)' ($r.Status -eq 200 -and @($r.Body.warnings).Count -eq 1 -and $r.Body.warnings[0] -match 'No phone number') "($($r.Status) $($r.Text))"

Step '3. SOAP faults from the CRM become JSON errors.'
$r = Send 'messages/customer-bad-email.json'
Check 'soap:Client fault -> HTTP 422 with the error code and field' ($r.Status -eq 422 -and $r.Body.faultcode -eq 'soap:Client' -and $r.Body.errorCode -eq 'INVALID_EMAIL' -and $r.Body.field -eq 'Email') "($($r.Status) $($r.Text))"
$r = Send 'messages/customer-unknown.json'
Check 'unknown customer -> HTTP 422 CUSTOMER_NOT_FOUND' ($r.Status -eq 422 -and $r.Body.errorCode -eq 'CUSTOMER_NOT_FOUND') "($($r.Status) $($r.Text))"
Control 'down'
$r = Send 'messages/customer-update.json'
Control 'up'
Check 'soap:Server fault -> HTTP 502, no error code' ($r.Status -eq 502 -and $r.Body.faultcode -eq 'soap:Server' -and $null -eq $r.Body.errorCode -and $r.Body.faultstring -match 'not available') "($($r.Status) $($r.Text))"

Complete-Demo
