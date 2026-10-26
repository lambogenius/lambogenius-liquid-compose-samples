<#
.SYNOPSIS
    Calls every workflow of the basics sample and checks each result. Start the sample first with ./run.ps1.
    Exits with 1 when a check fails.
#>
[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:7101')

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Set-Location $PSScriptRoot

function Send([string]$workflow) {
    $file = Get-ChildItem requests -Filter "$workflow.*" | Select-Object -First 1 -ExpandProperty FullName
    $r = Invoke-LiquidWorkflow $workflow $file -BaseUrl $BaseUrl
    Write-Host "  POST $workflow $(Split-Path $file -Leaf) -> HTTP $($r.Status)"
    $r
}

function Json($value) { $value | ConvertTo-Json -Depth 10 -Compress }

Step '1. JSON to JSON with a C# helper and a Function call (order-to-sales-order).'
$r = Send 'order-to-sales-order'
$order = $r.Body.salesOrder
Check 'HTTP 200' ($r.Status -eq 200) "($($r.Status) $($r.Text))"
Check 'order number and SKUs normalized by the C# helper' ($order.orderNumber -eq 'ORD-100' -and $order.lines[0].sku -eq 'ABC-01' -and $order.lines[1].sku -eq 'XYZ-02') (Json $r.Body)
Check 'customer name from the GetCustomerName Function, called once' ($order.customerName -eq 'Acme Supplies' -and $r.Body.functionCallCount -eq 1) (Json $r.Body)
Check 'currency from the action parameters, quantities stay numbers' ($order.currency -eq 'CAD' -and $order.lines[0].quantity -is [long]) (Json $r.Body)
Check 'later actions read typed fields of the result' ($r.Body.firstSku -eq 'ABC-01') (Json $r.Body)

Step '2. JSON to JSON with plain Liquid and a partial (plain-order-summary).'
$r = Send 'plain-order-summary'
Check 'HTTP 200 with totals' ($r.Status -eq 200 -and $r.Body.lineCount -eq 2 -and $r.Body.totalQuantity -eq 3 -and $r.Body.priority -eq $false) (Json $r.Body)
Check 'lines rendered by partials/line.liquid' ($r.Body.lines.Count -eq 2 -and $r.Body.lines[0].sku -eq 'abc-01') (Json $r.Body)

Step '3. JSON to text (order-to-text).'
$r = Send 'order-to-text'
$expected = "ORDER ORD-100`nCustomer: C100`n  1. abc-01 x 2`n  2. xyz-02 x 1`n    -- end of order --"
Check 'the exact text' ($r.Status -eq 200 -and ($r.Text -replace "`r", '').TrimEnd() -eq $expected) "($($r.Status))"
Show $r.Text

Step '4. XML to JSON with XPath and a namespace prefix (xml-order-to-json).'
$r = Send 'xml-order-to-json'
Check 'HTTP 200, a missing element is null, all SKUs as an array' ($r.Status -eq 200 -and $r.Body.orderNumber -eq 'ORD-100' -and $null -eq $r.Body.missing -and (Json $r.Body.skus) -eq '["abc-01","xyz-02"]' -and $r.Body.lineCount -eq 2) (Json $r.Body)

Step '5. XML to text (xml-order-to-text).'
$r = Send 'xml-order-to-text'
Check 'the exact text' ($r.Status -eq 200 -and ($r.Text -replace "`r", '').TrimEnd() -eq "Order ord-100`n- abc-01`n- xyz-02") "($($r.Status))"
Show $r.Text

Step '6. An inline template with three C# helpers (inline-csharp-helpers).'
$r = Send 'inline-csharp-helpers'
Check 'string, double and bool helpers' ($r.Status -eq 200 -and $r.Body.code -eq 'ABC-01' -and $r.Body.priceWithTax -eq 22.59 -and $r.Body.bulk -eq $true) (Json $r.Body)

Complete-Demo
