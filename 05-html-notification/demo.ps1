<#
.SYNOPSIS
    Sends the shipment events in messages/ and checks the emails the stand-in mail API received. Start the sample
    first with ./run.ps1. Exits with 1 when a check fails.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:7105',
    [string]$BackendUrl = 'http://127.0.0.1:8105'
)

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Set-Location $PSScriptRoot

function Send([string]$file) {
    $r = Invoke-LiquidWorkflow 'shipment-notification' $file -BaseUrl $BaseUrl
    Write-Host "  POST shipment-notification $(Split-Path $file -Leaf) -> HTTP $($r.Status)"
    $r
}

function Mail([string]$id) { (Invoke-RestMethod "$BackendUrl/received").messages | Where-Object messageId -eq $id }

try { Invoke-RestMethod -Method Post "$BackendUrl/control/reset" | Out-Null } catch { throw "The stand-in mail API is not answering on $BackendUrl. Start the sample with ./run.ps1 first." }

Step '1. An English shipment email: an HTML body (deployed template with partials) and a plain-text body (inline template).'
$r = Send 'messages/shipment-en.json'
Check 'HTTP 202, queued as MSG-1' ($r.Status -eq 202 -and $r.Body.messageId -eq 'MSG-1' -and $r.Body.subject -eq 'Your order WEB-1001 is on its way') "($($r.Status) $($r.Text))"
$mail = Mail 'MSG-1'
Check 'the gift message''s <script> arrives as text, not as HTML' ($mail.html -notmatch '<script' -and $mail.html -match '&lt;script&gt;alert\(&#39;hi&#39;\)&lt;/script&gt;Happy birthday!<br />')
Check 'item names escaped: <Pro>, & and quotes' ($mail.html -match 'Widget &lt;Pro&gt; &amp; carrying case' -and $mail.html -match 'Gizmo &quot;Mini&quot;')
Check 'tracking link built by a C# helper, spaces removed' ($mail.html -match 'href="https://www\.purolator\.com/en/shipping/tracker\?pin=PUR3301229901"')
Check 'delivery date written out' ($mail.html -match 'Saturday, October 24, 2026')
Check 'footer partial reads the action parameters' ($mail.html -match 'mailto:help@shop\.example' -and $mail.html -match 'Lambogenius Demo Shop')
Check 'the plain-text body keeps the message as written' ($mail.text -match "Happy birthday!`nFrom all of us" -and $mail.text -match "- 2 x Widget <Pro> & carrying case" -and $mail.text.EndsWith('-- Lambogenius Demo Shop'))
Write-Host "        Open it: $($r.Body.preview)" -ForegroundColor DarkGray

Step '2. The same event for a French-speaking customer, with no gift message.'
$r = Send 'messages/shipment-fr.json'
Check 'HTTP 202 with a French subject' ($r.Status -eq 202 -and $r.Body.subject -eq 'Votre commande WEB-1004 est en route') "($($r.Status) $($r.Text))"
$mail = Mail $r.Body.messageId
Check 'French text and a French date' ($mail.html -match '<html lang="fr">' -and $mail.html -match 'mardi 27 octobre 2026' -and $mail.text -match 'Bonjour Zoë,')
Check 'accented characters as HTML entities in the HTML body' ($mail.html -match 'Zo&#235;' -and $mail.html -match 'Cr&#232;me &#171; hiver &#187;')
Check 'no gift-message box' ($mail.html -notmatch 'message-cadeau')
Write-Host "        Open it: $($r.Body.preview)" -ForegroundColor DarkGray

Complete-Demo
