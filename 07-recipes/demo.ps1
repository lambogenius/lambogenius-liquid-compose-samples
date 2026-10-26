<#
.SYNOPSIS
    Calls every recipe workflow and checks the results, then runs each failure case of the error-handling workflow
    and checks its error code. Start the sample first with ./run.ps1. Exits with 1 when a check fails.
#>
[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:7107')

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Set-Location $PSScriptRoot

function Send([string]$workflow, [string]$file, [string]$query = '', [hashtable]$headers = @{}) {
    $r = Invoke-LiquidWorkflow $workflow $file -BaseUrl $BaseUrl -Query $query -Headers $headers
    $shown = if ($query) { "$workflow`?$query" } else { $workflow }
    Write-Host "  POST $shown $(Split-Path $file -Leaf) -> HTTP $($r.Status)"
    $r
}

function Json($value) { $value | ConvertTo-Json -Depth 10 -Compress }

Step '1. Liquid essentials: assign, capture, if, case, for (limit, offset, reversed) and filters.'
$r = Send 'liquid-essentials' 'messages/cart.json'
$b = $r.Body
Check 'HTTP 200; totals with Times and Plus' ($r.Status -eq 200 -and $b.itemCount -eq 3 -and $b.subtotal -eq 124.48 -and $b.average -eq 41.49) (Json $b)
Check 'capture, if / elsif and case / when' ($b.greeting -eq 'Hello Alex' -and $b.shipping -eq 'free shipping' -and $b.country -eq 'Canada') (Json $b)
Check 'for with limit, offset and reversed; forloop.index and length' ((Json $b.firstTwo) -eq '["ABC-01","XYZ-02"]' -and (Json $b.afterFirst) -eq '["XYZ-02","KIT-03"]' -and (Json $b.reversed) -eq '["KIT-03","XYZ-02","ABC-01"]' -and $b.numbered[2] -eq '3/3 Starter kit') (Json $b)
Check 'Map, Join, Split, Truncate, Replace, Remove, contains' ($b.skus -eq 'ABC-01,XYZ-02,KIT-03' -and (Json $b.tags) -eq '["spring","clearance","online"]' -and $b.shortNote -eq 'This is a gift fo...' -and $b.slug -eq 'this-is-a-gift-for-my-sister' -and $b.hasGift) (Json $b)

Step '2. Parameters from an app setting, workflow parameters, a header, the query string and expressions.'
$r = Send 'parameters' 'messages/order.json' 'mode=test' @{ 'x-tenant' = 'contoso' }
$b = $r.Body
Check 'app setting and workflow parameters (parameters.json), including an object' ($r.Status -eq 200 -and $b.environment -eq 'development' -and $b.region -eq 'canadacentral' -and $b.limits.maxLines -eq 500 -and $b.discountPercent -eq 12.5) (Json $b)
Check 'trigger header and query string' ($b.tenant -eq 'contoso' -and $b.mode -eq 'test') (Json $b)
Check 'expressions: utcNow() and workflow()' ([bool]$b.receivedAt -and $b.workflow -eq 'parameters') (Json $b)
$r = Send 'parameters' 'messages/order.json'
Check 'no header and no query: the template''s Default values' ($r.Body.tenant -eq 'unknown' -and $r.Body.mode -eq 'normal') (Json $r.Body)

Step '3. Partials: one partial used twice, and a partial that includes another.'
$r = Send 'partials' 'messages/order.json'
Check 'billTo and shipTo through partials/party.liquid and partials/address.liquid' ($r.Status -eq 200 -and $r.Body.billTo.name -eq 'Acme Supplies' -and $r.Body.shipTo.address.city -eq 'Mississauga' -and $r.Body.shipTo.address.postalCode -eq 'L5T 2H6') (Json $r.Body)

Step '4. Template versions: the same template name through two connections, each with its own templateFolder.'
$r = Send 'template-versions' 'messages/order.json'
Check 'v1/receipt.liquid and v2/receipt.liquid' ($r.Status -eq 200 -and $r.Body.v1.version -eq 1 -and $r.Body.v1.receipt -eq 'SO-2001' -and $r.Body.v2.version -eq 2 -and $r.Body.v2.amount.currency -eq 'CAD') (Json $r.Body)

Step '5. XPath: attributes, positions, predicates, two namespaces, CDATA, nothing found.'
$r = Send 'xpath' 'messages/shipment.xml'
$b = $r.Body
Check 'attributes and positions' ($r.Status -eq 200 -and $b.id -eq 'SHP-778' -and $b.firstPackage -eq '2.5' -and $b.secondPackage -eq '11' -and (Json $b.weightUnits) -eq '["kg","kg","lb"]') (Json $b)
Check 'predicates on attributes and on child elements' ((Json $b.fragileLabels) -eq '["A","C"]' -and $b.billingCity -eq 'Toronto' -and $b.shippingCity -eq 'Ottawa' -and $b.packageOfLabelB -eq '2') (Json $b)
Check 'CDATA text; null and [] when nothing matches; Size of XmlValues' ($b.instructions -eq 'Ring twice & leave <inside> the porch.' -and $null -eq $b.missing -and @($b.noMatches).Count -eq 0 -and $b.packageCount -eq 3) (Json $b)

Step '6. ToJson: escaping and types.'
$r = Send 'tojson' 'messages/tojson.json'
$b = $r.Body
$expected = Get-Content 'messages/tojson.json' -Raw | ConvertFrom-Json
Check 'quotes, backslashes, line breaks, tabs and Unicode round-trip' ($r.Status -eq 200 -and $b.quotes -ceq $expected.quotes -and $b.backslash -ceq 'C:\temp\new' -and $b.lineBreaks -ceq $expected.lineBreaks -and $b.unicode -ceq $expected.unicode -and $b.html -ceq $expected.html) (Json $b)
Check 'numbers, Booleans and null keep their types' ($b.integer -eq 42 -and $b.decimal -eq 19.99 -and $b.yes -is [bool] -and $b.yes -and -not $b.no -and $null -eq $b.nothing -and $null -eq $b.missing -and $b.emptyString -eq '' -and $b.numberAsText -is [string]) (Json $b)
Check 'arrays and objects as JSON' ((Json $b.list) -eq '[1,"two",null,{"three":3}]' -and $b.object.nested.deep[0] -eq $true) (Json $b)
Check 'a 20-digit integer is written exactly' ($r.Text -match '"large":\s*12345678901234567890[,\s}]') $r.Text

Step '7. Error handling: each case fails in its own way, and the workflow reads the error code.'
$cases = [ordered]@{
    'template-missing'     = 'TemplateNotFound'
    'syntax-error'         = 'TemplateSyntaxError'
    'unknown-filter'       = 'UnknownFilter'
    'invalid-json-output'  = 'InvalidOutputJson'
    'scripts-disabled'     = 'ScriptsDisabled'
    'helper-throws'        = 'ScriptExecutionFailed'
    'slow-helper'          = 'TransformationTimeout'
    'function-not-allowed' = 'FunctionNotAllowed'
    'unknown-customer'     = 'FunctionHttpFailed'
}
foreach ($case in $cases.Keys) {
    $r = Send 'error-handling' 'messages/error-case.json' "case=$case"
    Check "$case -> $($cases[$case]) (action $($r.Body.actionStatus), status $($r.Body.statusCode))" ($r.Status -eq 200 -and $r.Body.code -eq $cases[$case]) "($($r.Status) $($r.Text))"
}

Complete-Demo
