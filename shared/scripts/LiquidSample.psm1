<#
    Shared helpers for the samples' run.ps1 and demo.ps1 scripts.

    Start-LiquidSample builds and runs one sample Logic App with what it needs: Azurite, the GetCustomerName Function
    and the sample's stand-in APIs (backends/app.py). Invoke-LiquidWorkflow calls a workflow's HTTP trigger.
    Step, Check and Complete-Demo print a demo's checks and set its exit code.
#>

$ErrorActionPreference = 'Stop'
$script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$script:Failures = 0

function Find-Tool([string]$name, [string]$hint) {
    # npm installs PowerShell and cmd shims; Start-Process needs the .exe or .cmd.
    $tool = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Where-Object Extension -in '.exe', '.cmd', '' |
        Sort-Object { $_.Extension -ne '.exe' } | Select-Object -First 1
    if (-not $tool) { throw "$name was not found on PATH. $hint" }
    $tool.Source
}

function Test-Listening([int]$port) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try { $client.ConnectAsync('127.0.0.1', $port).Wait(300) -and $client.Connected } catch { $false } finally { $client.Dispose() }
}

function Wait-Until([scriptblock]$condition, [string]$what, [int]$seconds = 120) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while (-not (& $condition)) {
        if ((Get-Date) -gt $deadline) { throw "Timed out waiting for $what." }
        Start-Sleep -Milliseconds 500
    }
}

function Get-LiquidPackageVersion([string]$app) {
    [xml]$project = Get-Content (Join-Path $app 'LogicApp.csproj')
    $version = $project.Project.PropertyGroup | ForEach-Object { $_.LiquidComposeVersion } | Where-Object { $_ } | Select-Object -First 1
    if ($version -is [System.Xml.XmlElement]) { $version = $version.'#text' }
    if ($version) { $version } else { '0.1.1' }
}

<#
.SYNOPSIS
    Builds one sample Logic App and runs it with `func start` in the current window. Ctrl+C stops it and whatever
    this function started; an Azurite or Function that was already running is left alone.
#>
function Start-LiquidSample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][int]$Port,
        [switch]$UsesFunction,
        [int]$FunctionPort = 7075,
        [int]$BackendPort = 0,
        [string[]]$Examples = @(),
        [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug'
    )

    $logs = Join-Path $App 'logs'
    $started = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

    # 1. Prerequisites.
    if (-not ((dotnet --list-sdks) -match '^8\.')) { throw '.NET SDK 8 is required: https://dotnet.microsoft.com/download/dotnet/8.0' }
    $func = Find-Tool 'func' 'Install Azure Functions Core Tools 4: npm install -g azure-functions-core-tools@4'
    $python = if ($BackendPort) { Find-Tool 'python' 'Install Python 3: https://www.python.org/downloads/' }
    Write-Host "dotnet $((dotnet --version)), func $((& $func --version))$(if ($python) { ", $((& $python --version))" })"
    New-Item -ItemType Directory -Force $logs | Out-Null

    # 2. The Compose using Liquid package, downloaded from lambogenius.com into packages/.
    $version = Get-LiquidPackageVersion $App
    $package = Join-Path $script:RepoRoot "packages/Lambogenius.LiquidCompose.LogicApps.$version.nupkg"
    if (-not (Test-Path $package)) {
        throw "packages/Lambogenius.LiquidCompose.LogicApps.$version.nupkg is missing. Sign in at https://lambogenius.com/app/downloads/liquid-compose, download it, and save it in $(Join-Path $script:RepoRoot 'packages')."
    }

    try {
        # 3. Storage emulator.
        $storagePorts = 10000, 10001, 10002
        $busy = @($storagePorts | Where-Object { Test-Listening $_ })
        if ($busy.Count -eq $storagePorts.Count) {
            Write-Host 'Storage emulator: using the one already listening on ports 10000-10002.'
        }
        else {
            if ($busy) {
                # Another program holds some of the default ports (VS Code sometimes holds 10001), so Azurite gets free
                # ones and the Logic App is pointed at them. Core Tools prefers this environment variable over
                # local.settings.json. The key is the emulator's public, well-known development account key.
                $first = 10100
                while (@($first..($first + 2) | Where-Object { Test-Listening $_ }).Count) { $first += 3 }
                $storagePorts = $first, ($first + 1), ($first + 2)
                Write-Host "Another program is using port(s) $($busy -join ', '); Azurite will listen on $($storagePorts -join ', ')."
                $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;' +
                    'AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;' +
                    "BlobEndpoint=http://127.0.0.1:$($storagePorts[0])/devstoreaccount1;" +
                    "QueueEndpoint=http://127.0.0.1:$($storagePorts[1])/devstoreaccount1;" +
                    "TableEndpoint=http://127.0.0.1:$($storagePorts[2])/devstoreaccount1;"
            }
            $azurite = Find-Tool 'azurite' 'Install Azurite: npm install -g azurite'
            $data = Join-Path $App '.azurite'
            New-Item -ItemType Directory -Force $data | Out-Null
            Write-Host "Starting Azurite (data in $data) ..."
            $started.Add((Start-Process $azurite -ArgumentList '--silent', '--skipApiVersionCheck', '--location', "`"$data`"",
                '--blobPort', $storagePorts[0], '--queuePort', $storagePorts[1], '--tablePort', $storagePorts[2] -PassThru -WindowStyle Hidden))
            Wait-Until { @($storagePorts | Where-Object { Test-Listening $_ }).Count -eq 3 } "Azurite on ports $($storagePorts -join ', ')" 60
        }

        # 4. The customer lookup that templates call with CallFunction: 'GetCustomerName'.
        if ($UsesFunction) {
            $functionUrl = "http://127.0.0.1:$FunctionPort/api/GetCustomerName"
            $answers = { try { (Invoke-WebRequest -Method Post -Uri $functionUrl -Body '{"value":"C100"}' -ContentType 'application/json' -TimeoutSec 5).Content -eq 'Acme Supplies' } catch { $false } }
            if (& $answers) {
                Write-Host "GetCustomerName Function: already running on port $FunctionPort."
            }
            else {
                $function = Join-Path $script:RepoRoot 'shared/functions/GetCustomerName'
                if (-not (Test-Path (Join-Path $function 'local.settings.json'))) { Copy-Item (Join-Path $function 'local.settings.sample.json') (Join-Path $function 'local.settings.json') }
                Write-Host "Building and starting the GetCustomerName Function on port $FunctionPort ..."
                dotnet build $function -v q --nologo | Out-Null
                if ($LASTEXITCODE) { throw 'The GetCustomerName Function failed to build.' }
                $started.Add((Start-Process $func -ArgumentList 'start', '--port', $FunctionPort -WorkingDirectory $function -PassThru -WindowStyle Hidden `
                    -RedirectStandardOutput (Join-Path $logs 'function.log') -RedirectStandardError (Join-Path $logs 'function.err.log')))
                Wait-Until $answers "the GetCustomerName Function (see $logs/function.log)" 180
            }
        }

        # 5. The sample's stand-in APIs.
        if ($BackendPort) {
            if (Test-Listening $BackendPort) { throw "Port $BackendPort (the stand-in APIs) is already in use. Stop what uses it, or pass -BackendPort <port> and change the URLs in local.settings.json." }
            Write-Host "Starting the stand-in APIs on port $BackendPort ..."
            $started.Add((Start-Process $python -ArgumentList '-u', "`"$(Join-Path $App 'backends/app.py')`"", '--port', $BackendPort -PassThru -WindowStyle Hidden `
                -RedirectStandardOutput (Join-Path $logs 'backends.log') -RedirectStandardError (Join-Path $logs 'backends.err.log')))
            Wait-Until { Test-Listening $BackendPort } "the stand-in APIs (see $logs/backends.err.log)" 30
        }

        # 6. Build and run the Logic App.
        if (-not (Test-Path (Join-Path $App 'local.settings.json'))) { Copy-Item (Join-Path $App 'local.settings.sample.json') (Join-Path $App 'local.settings.json') }
        if (Test-Listening $Port) { throw "Port $Port is already in use. Pass -Port <other port>." }
        Write-Host 'Building the Logic App ...'
        dotnet build (Join-Path $App 'LogicApp.csproj') -c $Configuration --nologo -v q
        if ($LASTEXITCODE) { throw 'The Logic App failed to build.' }

        Write-Host ''
        Write-Host "Starting the Logic App on http://localhost:$Port. In another window, try:" -ForegroundColor Green
        foreach ($example in $Examples) { Write-Host "  $example" -ForegroundColor Green }
        Write-Host '  ./demo.ps1        # every step, checked' -ForegroundColor Green
        Write-Host 'Press Ctrl+C to stop.' -ForegroundColor Green
        Write-Host ''
        Push-Location (Join-Path $App "bin/$Configuration/net8.0")
        try { & $func start --port $Port } finally { Pop-Location }
    }
    finally {
        foreach ($process in $started) {
            if (-not $process.HasExited) {
                Write-Host "Stopping $($process.ProcessName) (pid $($process.Id))"
                taskkill /PID $process.Id /T /F | Out-Null
            }
        }
    }
}

<#
.SYNOPSIS
    Posts a file to a workflow's HTTP trigger ("When_an_HTTP_request_is_received") and returns the status, the parsed
    body (JSON) or the text, the content type and the time taken.
#>
function Invoke-LiquidWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Workflow,
        [Parameter(Mandatory, Position = 1)][string]$File,
        [Parameter(Mandatory)][string]$BaseUrl,
        [string]$Query = '',
        [hashtable]$Headers = @{}
    )

    $path = (Resolve-Path $File).Path
    $contentType = switch -Wildcard ($path) { '*.xml' { 'application/xml' } '*.json' { 'application/json' } default { 'text/plain' } }
    # Request triggers need a signed URL; the local runtime hands it out through its management API.
    try {
        $url = (Invoke-RestMethod -Method Post -Uri "$BaseUrl/runtime/webhooks/workflow/api/management/workflows/$Workflow/triggers/When_an_HTTP_request_is_received/listCallbackUrl?api-version=2020-05-01-preview").value
    }
    catch {
        throw "Could not reach the Logic App at $BaseUrl, or it has no workflow '$Workflow'. Is ./run.ps1 running? $($_.Exception.Message)"
    }
    if ($Query) { $url += "&$Query" }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Method Post -Uri $url -InFile $path -ContentType $contentType -Headers $Headers -SkipHttpErrorCheck
    $type = "$($response.Headers['Content-Type'])"
    $text = if ($response.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($response.Content) } else { $response.Content }
    [pscustomobject]@{
        Status      = [int]$response.StatusCode
        ContentType = $type
        Headers     = $response.Headers
        Text        = $text
        Body        = if ($type -like '*json*' -and $text) { $text | ConvertFrom-Json } else { $text }
        Seconds     = $watch.Elapsed.TotalSeconds
    }
}

<#
.SYNOPSIS
    Prints a workflow response (used by the samples' send.ps1).
#>
function Write-LiquidResponse([string]$workflow, [string]$file, $response) {
    $color = if ($response.Status -lt 300) { 'Green' } else { 'Red' }
    Write-Host "POST $workflow $(Split-Path $file -Leaf) -> HTTP $($response.Status)" -ForegroundColor $color
    if ($response.ContentType -like '*json*' -and $response.Text) { $response.Body | ConvertTo-Json -Depth 20 } else { $response.Text }
}

function Step([string]$title) { Write-Host ''; Write-Host $title -ForegroundColor Cyan }

function Check([string]$what, [bool]$ok, [string]$actual = '') {
    if ($ok) { Write-Host "  ok    $what" -ForegroundColor Green }
    else { Write-Host "  FAIL  $what $actual" -ForegroundColor Red; $script:Failures++ }
}

function Show([string]$text) { Write-Host ($text.TrimEnd() -replace '(?m)^', '        ') -ForegroundColor DarkGray }

function Complete-Demo {
    Write-Host ''
    if ($script:Failures) { Write-Host "$script:Failures check(s) failed." -ForegroundColor Red; exit 1 }
    Write-Host 'All checks passed.' -ForegroundColor Green
    exit 0
}

Export-ModuleMember -Function Start-LiquidSample, Invoke-LiquidWorkflow, Write-LiquidResponse, Step, Check, Show, Complete-Demo, Test-Listening
