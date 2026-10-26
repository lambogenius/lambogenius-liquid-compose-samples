<#
.SYNOPSIS
    Runs every step of the orders-to-ERP scenario against the running app and checks the results.

.DESCRIPTION
    Start the sample first with ./run.ps1 (in another window). This script resets the stand-in ERP and warehouse,
    then sends the orders in messages/ and checks what the caller, the ERP and the warehouse each received.
    It exits with 1 when a check fails.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:7102',
    [string]$BackendUrl = 'http://127.0.0.1:8102'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Set-Location $PSScriptRoot

function Send([string]$workflow, [string]$file) {
    $r = Invoke-LiquidWorkflow $workflow $file -BaseUrl $BaseUrl
    Write-Host "  POST $workflow $(Split-Path $file -Leaf) -> HTTP $($r.Status) in $([math]::Round($r.Seconds, 1)) s"
    $r
}

function Received { Invoke-RestMethod "$BackendUrl/received" }
function Control([string]$what) { Invoke-RestMethod -Method Post "$BackendUrl/control/$what" | Out-Null }

try { Control 'reset' } catch { throw "The stand-in ERP is not answering on $BackendUrl. Start the sample with ./run.ps1 first." }

Step '1. A webshop order becomes an ERP sales order and a pick list.'
$r = Send 'webshop-order' 'messages/webshop-order.json'
Check 'HTTP 201 with an ERP order id' ($r.Status -eq 201 -and $r.Body.erpOrderId -eq 'SO-000101') "($($r.Status) $($r.Body | ConvertTo-Json -Compress))"
Check 'customer name came from the GetCustomerName Function' ($r.Body.customerName -eq 'Acme Supplies')
$erp = (Received).salesOrders | Where-Object { $_.order.externalOrderId -eq 'WEB-1001' }
Check 'the ERP got WEB-1001 with cleaned-up data (C# helpers)' ($erp.order.shipTo.postalCode -eq 'M5X 1A9' -and $erp.order.taxCode -eq 'HST13' -and $erp.order.lines[0].item -eq 'ABC-01' -and $erp.order.lines[0].unitPrice -eq 9.99 -and $erp.order.orderDate -eq '2026-10-20') ($erp.order | ConvertTo-Json -Compress -Depth 5)
$pick = (Received).pickLists | Where-Object salesOrderId -eq 'SO-000101'
Check 'the warehouse got a text pick list' ($pick.text -match 'PICK LIST SO-000101' -and $pick.text -match 'Units: 3')
Show $pick.text

Step '2. A partner purchase order (XML) gets the same treatment and an XML acknowledgement.'
$r = Send 'partner-order' 'messages/partner-po.xml'
$ack = [xml]$r.Body
Check 'HTTP 201 with an XML acknowledgement' ($r.Status -eq 201 -and $ack.PurchaseOrderAck.Status -eq 'Accepted' -and $ack.PurchaseOrderAck.SupplierOrderId -eq 'SO-000102') "($($r.Status) $($r.Body))"
Check 'three acknowledged lines' (@($ack.PurchaseOrderAck.Lines.Line).Count -eq 3)
$erp = (Received).salesOrders | Where-Object { $_.order.externalOrderId -eq 'EDI-PO-7731' }
Check 'the ERP got EDI-PO-7731 with numbers, not strings' ($erp.order.lines[0].quantity -eq 24 -and $erp.order.lines[1].unitPrice -eq 4.25 -and $erp.order.customer.name -eq 'Globex Corporation')

Step '3. The webshop sends the same order again.'
$r = Send 'webshop-order' 'messages/webshop-order.json'
Check 'HTTP 200 "already received" with the same ERP order id' ($r.Status -eq 200 -and $r.Body.status -eq 'already received' -and $r.Body.erpOrderId -eq 'SO-000101') "($($r.Status) $($r.Body | ConvertTo-Json -Compress))"
Check 'the ERP still has two orders' (@((Received).salesOrders).Count -eq 2)

Step '4. An order shipped to Québec, for a customer with accents and quotes in its name.'
$r = Send 'webshop-order' 'messages/webshop-order-quebec.json'
Check 'HTTP 201' ($r.Status -eq 201) "($($r.Status))"
Check 'the name is intact' ($r.Body.customerName -eq 'Initech "Québec" Ltée') $r.Body.customerName
$erp = (Received).salesOrders | Where-Object { $_.order.externalOrderId -eq 'WEB-1004' }
Check 'Québec tax code and postal code' ($erp.order.taxCode -eq 'GST-QST' -and $erp.order.shipTo.postalCode -eq 'H2Y 1C6' -and $erp.order.shipTo.city -eq 'Montréal')

Step '5. An unknown customer: the map fails and nothing reaches the ERP.'
$before = @((Received).salesOrders).Count
$r = Send 'webshop-order' 'messages/webshop-order-unknown-customer.json'
Check 'HTTP 422 naming the Function failure' ($r.Status -eq 422 -and $r.Body.detail.message -match 'FunctionHttpFailed' -and $r.Body.detail.message -match 'HTTP 404') "($($r.Status) $($r.Body | ConvertTo-Json -Compress))"
Check 'the ERP got nothing' (@((Received).salesOrders).Count -eq $before)

Step '6. The ERP rejects an order with a zero quantity.'
$r = Send 'webshop-order' 'messages/webshop-order-zero-quantity.json'
Check "HTTP 422 with the ERP's reason" ($r.Status -eq 422 -and $r.Body.failure -eq 'erp-rejected' -and "$($r.Body.erp.problems)" -match 'quantity') "($($r.Status) $($r.Body | ConvertTo-Json -Compress))"

Step '7. The ERP is down.'
$calls = (Received).calls.'/erp/salesorders'
Control 'erp-down'
$r = Send 'partner-order' 'messages/partner-po.xml'
Control 'erp-up'
$calls = (Received).calls.'/erp/salesorders' - $calls
Check 'HTTP 503 telling the partner to send again later' ($r.Status -eq 503 -and $r.Body.failure -eq 'erp-unavailable') "($($r.Status) $($r.Body | ConvertTo-Json -Compress))"
Check 'the ERP got 3 calls: the first and 2 retries, 5 s apart (the child workflow is not retried)' ($calls -eq 3) "($calls calls)"
Check 'answered in seconds, not after a gateway timeout' ($r.Seconds -lt 30) "($([int]$r.Seconds) s)"

Step '8. The warehouse is down after the ERP accepted the order; sending again completes it.'
Control 'warehouse-down'
$r = Send 'webshop-order' 'messages/webshop-order-quebec.json'
Control 'warehouse-up'
Check 'HTTP 502 naming the ERP order that was created' ($r.Status -eq 502 -and $r.Body.failure -eq 'warehouse' -and $r.Body.erpOrderId -eq 'SO-000103') "($($r.Status) $($r.Body | ConvertTo-Json -Compress))"
$r = Send 'webshop-order' 'messages/webshop-order-quebec.json'
Check 'sending again: HTTP 200, same ERP order, no duplicate' ($r.Status -eq 200 -and $r.Body.erpOrderId -eq 'SO-000103')
Check 'the warehouse now has the pick list' ([bool]((Received).pickLists | Where-Object salesOrderId -eq 'SO-000103'))

Complete-Demo
