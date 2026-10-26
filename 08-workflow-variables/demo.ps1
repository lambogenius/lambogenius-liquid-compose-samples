<#
.SYNOPSIS
    Runs every workflow of the workflow variables sample and checks the answers. Start the sample first with
    ./run.ps1. Exits with 1 when a check fails.
#>
[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:7108')

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Set-Location $PSScriptRoot

function Send([string]$workflow, [string]$file, [string]$query = '', [hashtable]$headers = @{}) {
    $r = Invoke-LiquidWorkflow $workflow $file -BaseUrl $BaseUrl -Query $query -Headers $headers
    Write-Host "  POST $workflow $(Split-Path $file -Leaf)$(if ($query) { "?$query" }) -> HTTP $($r.Status)"
    $r
}

Step '1. Variables of every type as template parameters.'
$r = Send 'variables-as-parameters' 'messages/order.json' 'maxLines=4&exclude=GIFT-WRAP' @{ 'x-expedite' = 'true' }
$q = $r.Body.quote
Check 'HTTP 200' ($r.Status -eq 200) "($($r.Status) $($r.Text))"
Check 'integer maxLines: only the first 4 of 5 lines are read' ($q.linesInOrder -eq 5 -and $q.lines[-1].sku -eq 'MN-270') "($($q.lines.sku -join ', '))"
Check 'array excludedSkus: GIFT-WRAP left out, 3 lines quoted' ($q.lineCount -eq 3 -and $q.lines.sku -notcontains 'GIFT-WRAP')
Check 'float taxRate 0.15 and boolean expedite: tax 143.39, shipping 25, total 1124.35' ($q.tax -eq 143.39 -and $q.shipping -eq 25 -and $q.total -eq 1124.35 -and $q.expedite -eq $true) "($($q.tax) $($q.shipping) $($q.total))"
Check 'object shipTo read field by field' ($q.shipTo -eq 'Halifax, NS')
Check 'the typed result set the float and integer variables' ($r.Body.variables.total -eq 1124.35 -and $r.Body.variables.lineCount -eq 3) "($($r.Body.variables | ConvertTo-Json -Compress))"
Show ($r.Body | ConvertTo-Json -Depth 5)

$r = Send 'variables-as-parameters' 'messages/order.json' 'currency=usd&taxRate=0.05'
$q = $r.Body.quote
Check 'other values, same template: USD, every line, 5% tax, no expedite' ($q.currency -eq 'USD' -and $q.lineCount -eq 5 -and $q.tax -eq 51.87 -and $q.shipping -eq 0 -and $q.total -eq 1089.33) "($($r.Text))"

Step '2. A For each loop that fills array, integer and float variables, then a report from the array.'
$r = Send 'batch-loop' 'messages/batch.json'
Check 'HTTP 200, text/plain' ($r.Status -eq 200 -and $r.ContentType -like 'text/plain*') "($($r.Status) $($r.Text))"
Check 'orderCount 3 (integer), batchTotal 1337.97 (float), the cancelled order in skipped (array)' ("$($r.Headers['x-order-count'])" -eq '3' -and "$($r.Headers['x-batch-total'])" -eq '1337.97' -and "$($r.Headers['x-skipped'])" -eq 'SO-2026-0822') "($($r.Headers['x-order-count']) $($r.Headers['x-batch-total']) $($r.Headers['x-skipped']))"
Check 'the report lists the orders in order, numbered from the counter' ($r.Text -match '(?m)^1\. SO-2026-0821' -and $r.Text -match '(?m)^2\. SO-2026-0823' -and $r.Text -match '(?m)^3\. SO-2026-0824  Adventure Works  3 line\(s\)  201\.99')
Check 'a header line and a skipped line' ($r.Text -match '^Batch B-20261025-01: 3 orders, 1337\.97 CAD' -and $r.Text -match 'Skipped \(cancelled\): SO-2026-0822')
Show $r.Text

Step '3. A variable chooses the template and the output format.'
$r = Send 'dynamic-template' 'messages/order.json' 'format=json'
Check 'json: formats/order-json.liquid, a JSON object' ($r.Status -eq 200 -and $r.ContentType -like 'application/json*' -and $r.Body.lines.Count -eq 5 -and "$($r.Headers['x-template'])" -eq 'formats/order-json.liquid') "($($r.Status) $($r.Text))"
$r = Send 'dynamic-template' 'messages/order.json' 'format=csv'
Check 'csv: text/csv with a header and 5 rows' ($r.Status -eq 200 -and $r.ContentType -like 'text/csv*' -and ($r.Text.Trim() -split "`n").Count -eq 6 -and $r.Text.StartsWith('order,sku,quantity,unitPrice')) "($($r.Status) $($r.Text))"
Show $r.Text
$r = Send 'dynamic-template' 'messages/order.json' 'format=text'
Check 'text: a plain-text summary' ($r.Status -eq 200 -and $r.Text -match '4 x Keyboard \(KB-100\)') "($($r.Status) $($r.Text))"
$r = Send 'dynamic-template' 'messages/order.json' 'format=pdf'
Check 'pdf: no such template, HTTP 400 with TemplateNotFound' ($r.Status -eq 400 -and $r.Body.code -eq 'TemplateNotFound') "($($r.Status) $($r.Text))"

Step '4. A one-word decision from the template, and a Switch on it.'
$cases = @(
    @{ File = 'expense-meal'; Decision = 'auto'; Route = 'payments' }
    @{ File = 'expense-no-receipt'; Decision = 'review'; Route = 'manager-review' }
    @{ File = 'expense-travel'; Decision = 'review'; Route = 'manager-review' }
    @{ File = 'expense-gift'; Decision = 'reject'; Route = 'returned-to-employee' }
    @{ File = 'expense-large'; Decision = 'reject'; Route = 'returned-to-employee' }
)
foreach ($case in $cases) {
    $r = Send 'approval-routing' "messages/$($case.File).json"
    Check "$($case.File): $($case.Decision), routed to $($case.Route)" ($r.Status -eq 200 -and $r.Body.decision -ceq $case.Decision -and $r.Body.route -eq $case.Route) "($($r.Status) $($r.Text))"
}
Check 'rules from an app setting (100) and workflow parameters (5000; gifts and alcohol)' ($r.Body.rules.autoApproveLimit -eq 100 -and $r.Body.rules.reviewLimit -eq 5000 -and ($r.Body.rules.blockedCategories -join ',') -eq 'gifts,alcohol')

Complete-Demo
