<#
.SYNOPSIS
    Creates the CSV and the bank file and compares them byte for byte with expected/. Start the sample first with
    ./run.ps1. Exits with 1 when a check fails.
#>
[CmdletBinding()]
param([string]$BaseUrl = 'http://localhost:7103')

Import-Module (Join-Path $PSScriptRoot '../shared/scripts/LiquidSample.psm1') -Force
Set-Location $PSScriptRoot

function Send([string]$workflow, [string]$file) {
    $r = Invoke-LiquidWorkflow $workflow $file -BaseUrl $BaseUrl
    Write-Host "  POST $workflow $(Split-Path $file -Leaf) -> HTTP $($r.Status)"
    $r
}

function Visible([string]$text) { $text.Replace("`r", '<CR>').Replace("`n", "<LF>`n") }

Step '1. Orders to a CSV file for finance (JSON to text).'
$r = Send 'orders-to-csv' 'messages/orders.json'
$expected = [System.IO.File]::ReadAllText((Resolve-Path 'expected/orders.csv'))
Check 'HTTP 200, text/csv, named after the export date' ($r.Status -eq 200 -and $r.ContentType -like 'text/csv*' -and "$($r.Headers['Content-Disposition'])" -match 'orders-20261021\.csv') "($($r.Status) $($r.ContentType) $($r.Headers['Content-Disposition']))"
Check 'byte for byte the same as expected/orders.csv' ($r.Text -ceq $expected)
Check 'CRLF after every record, a bare LF only inside a quoted note' (([regex]::Matches($r.Text, "`r`n")).Count -eq 4 -and $r.Text -match '"Two lines:\nfirst')
Check 'commas and quotes quoted, money with two decimals, a missing currency defaulted' ($r.Text -match '"Globex, Corporation"' -and $r.Text -match '"Initech ""Québec"" Ltée"' -and $r.Text -match ',45\.50,CAD,')
Show (Visible $r.Text)

Step '2. Payments to the bank''s fixed-width file.'
$r = Send 'payments-to-bank-file' 'messages/payments.json'
$expected = [System.IO.File]::ReadAllText((Resolve-Path 'expected/payments.txt'))
Check 'HTTP 200 with a header, three payments and a trailer' ($r.Status -eq 200 -and "$($r.Headers['x-record-count'])" -eq '5') "($($r.Status) $($r.Text))"
Check 'byte for byte the same as expected/payments.txt' ($r.Text -ceq $expected)
$records = $r.Text -split "`r`n" | Where-Object { $_ }
Check 'every record is 80 characters' (@($records | Where-Object { $_.Length -ne 80 }).Count -eq 0 -and $records.Count -eq 5)
Check 'payee names in ASCII, long ones cut to 30 characters' ($records[2].Substring(13, 30) -ceq 'INITECH "QUEBEC" LTEE         ' -and $records[3].Substring(13, 30) -ceq 'GLOBEX CORPORATION OF NORTH AM')
Check 'trailer: 3 payments, 1,340.00 in cents' ($records[4].Substring(0, 21) -eq 'T00000300000000134000')
Show (Visible $r.Text)

Step '3. A payment with an account number that has no digits.'
$r = Send 'payments-to-bank-file' 'messages/payments-bad-account.json'
Check 'HTTP 422: the C# helper threw, so no file was created' ($r.Status -eq 422 -and $r.Body.code -eq 'ScriptExecutionFailed' -and $r.Body.message -match "helper 'Account'") "($($r.Status) $($r.Text))"

Complete-Demo
