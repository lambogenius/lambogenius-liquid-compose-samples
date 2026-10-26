<#
.SYNOPSIS
    Sends the invoices in messages/ and checks what the supplier and accounts payable each got. Start the sample
    first with ./run.ps1. Exits with 1 when a check fails.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:7104',
    [string]$BackendUrl = 'http://127.0.0.1:8104'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Set-Location $PSScriptRoot

function Send([string]$file) {
    $r = Invoke-LiquidWorkflow 'supplier-invoice' $file -BaseUrl $BaseUrl
    Write-Host "  POST supplier-invoice $(Split-Path $file -Leaf) -> HTTP $($r.Status)"
    $r
}

function Received { Invoke-RestMethod "$BackendUrl/received" }
function Json($value) { $value | ConvertTo-Json -Depth 10 -Compress }

try { Invoke-RestMethod -Method Post "$BackendUrl/control/reset" | Out-Null } catch { throw "The stand-in accounts payable API is not answering on $BackendUrl. Start the sample with ./run.ps1 first." }

Step '1. A UBL 2.1 invoice (XML, default namespace plus cac and cbc) becomes the JSON accounts payable expects.'
$r = Send 'messages/invoice.xml'
Check 'HTTP 201 with the AP invoice id' ($r.Status -eq 201 -and $r.Body.apInvoiceId -eq 'AP-5001' -and $r.Body.total -eq 1497.25) "($($r.Status) $($r.Text))"
$invoice = ((Received).invoices | Where-Object apInvoiceId -eq 'AP-5001').invoice
Check 'header fields, 30-day terms worked out by a C# helper' ($invoice.supplierInvoiceNumber -eq 'INV-88123' -and $invoice.purchaseOrder -eq 'PO-2026-0457' -and $invoice.paymentTermsDays -eq 30 -and $invoice.supplier.email -eq 'billing@northwind.example') (Json $invoice)
Check 'amounts are numbers, not strings' ($invoice.subtotal -eq 1325 -and $invoice.tax -eq 172.25 -and $invoice.lines[1].quantity -eq 2.5 -and $invoice.lines[1].quantity -is [double]) (Json $invoice)
Check 'unit codes from an attribute (@unitCode), translated' ($invoice.lines[0].unit -eq 'each' -and $invoice.lines[1].unit -eq 'hour') (Json $invoice.lines)
Check 'XML entities decoded: & and <on site>' ($invoice.note -eq 'Thank you & see you soon' -and $invoice.lines[1].description -eq 'Installation <on site>') (Json $invoice)

Step '2. The supplier sends the same invoice again.'
$r = Send 'messages/invoice.xml'
Check 'HTTP 409 with the AP invoice id it already has' ($r.Status -eq 409 -and $r.Body.accountsPayable.apInvoiceId -eq 'AP-5001') "($($r.Status) $($r.Text))"

Step '3. An invoice without a purchase order reference: the map fails, nothing reaches accounts payable.'
$before = (Received).calls.'/ap/invoices'
$r = Send 'messages/invoice-missing-po.xml'
Check 'HTTP 422: the Required helper stopped the map' ($r.Status -eq 422 -and $r.Body.code -eq 'ScriptExecutionFailed' -and $r.Body.message -match "helper 'Required' threw") "($($r.Status) $($r.Text))"
Check 'accounts payable got no call' ((Received).calls.'/ap/invoices' -eq $before)

Step '4. Invoices accounts payable rejects: an unknown purchase order, a total that does not add up.'
$r = Send 'messages/invoice-unknown-po.xml'
Check "HTTP 422 with accounts payable's reason" ($r.Status -eq 422 -and "$($r.Body.accountsPayable.problems)" -match 'PO-1999-0001 is not open') "($($r.Status) $($r.Text))"
$r = Send 'messages/invoice-wrong-total.xml'
Check 'HTTP 422: subtotal + tax is not the total' ($r.Status -eq 422 -and "$($r.Body.accountsPayable.problems)" -match '1497.25, not the total 1479.25') "($($r.Status) $($r.Text))"

Complete-Demo
