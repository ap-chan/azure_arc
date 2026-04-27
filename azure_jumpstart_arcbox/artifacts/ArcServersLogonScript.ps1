$ErrorActionPreference = $env:ErrorActionPreference

# Import helper module containing wallpaper and common functions
Import-Module Azure.Arc.Jumpstart.Common -ErrorAction SilentlyContinue

$Env:ArcBoxDir = 'C:\ArcBox'
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$Env:ArcBoxVMDir = 'F:\Virtual Machines'
$Env:ArcBoxIconDir = "$Env:ArcBoxDir\Icons"
$Env:ArcBoxTestsDir = "$Env:ArcBoxDir\Tests"
$Env:ArcBoxDscDir = "$Env:ArcBoxDir\DSC"
$agentScript = "$Env:ArcBoxDir\agentScript"

# Set variables to execute remote powershell scripts on guest VMs
$nestedVMArcBoxDir = $Env:ArcBoxDir
$tenantId = $env:tenantId
$subscriptionId = $env:subscriptionId
$azureLocation = $env:azureLocation
$resourceGroup = $env:resourceGroup
$resourceTags = $env:resourceTags
$namingPrefix = $env:namingPrefix

# Determine ARM endpoint based on Azure environment (Gov vs Commercial)
$azureEnvironment = $env:azureEnvironment
$armEndpoint = if ($azureEnvironment -eq 'AzureUSGovernment') { 'https://management.usgovcloudapi.net' } else { 'https://management.azure.com' }

# Moved VHD storage account details here to keep only in place to prevent duplicates.
# NOTE: The VHD source storage account (jumpstartprodsg) is in public Azure,
# so the URL always uses blob.core.windows.net regardless of target environment.
$vhdSourceFolder = 'https://jumpstartprodsg.blob.core.windows.net/arcbox/prod/*'

# Archive existing log file and create new one
$logFilePath = "$Env:ArcBoxLogsDir\ArcServersLogonScript.log"
if (Test-Path $logFilePath) {
    $archivefile = "$Env:ArcBoxLogsDir\ArcServersLogonScript-" + (Get-Date -Format 'yyyyMMddHHmmss')
    Rename-Item -Path $logFilePath -NewName $archivefile -Force
}

Start-Transcript -Path $logFilePath -Force -ErrorAction SilentlyContinue

# Refresh PATH to ensure tools installed by WinGet.ps1 (az, azcopy, etc.) are available
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

# Remove registry keys that are used to automatically logon the user (only used for first-time setup)
$registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$keys = @('AutoAdminLogon', 'DefaultUserName', 'DefaultPassword')

foreach ($key in $keys) {
    try {
        $property = Get-ItemProperty -Path $registryPath -Name $key -ErrorAction Stop
        Remove-ItemProperty -Path $registryPath -Name $key
        Write-Host "Removed registry key that are used to automatically logon the user: $key"
    } catch {
        Write-Verbose "Key $key does not exist."
    }
}

# Create desktop shortcut for Logs-folder
$WshShell = New-Object -ComObject WScript.Shell
$LogsPath = 'C:\ArcBox\Logs'
$Shortcut = $WshShell.CreateShortcut("$Env:USERPROFILE\Desktop\Logs.lnk")
$Shortcut.TargetPath = $LogsPath
$shortcut.WindowStyle = 3
$shortcut.Save()

# Configure Windows Terminal as the default terminal application
$registryPath = 'HKCU:\Console\%%Startup'

if (Test-Path $registryPath) {
    Set-ItemProperty -Path $registryPath -Name 'DelegationConsole' -Value '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'
    Set-ItemProperty -Path $registryPath -Name 'DelegationTerminal' -Value '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'
} else {
    New-Item -Path $registryPath -Force | Out-Null
    Set-ItemProperty -Path $registryPath -Name 'DelegationConsole' -Value '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'
    Set-ItemProperty -Path $registryPath -Name 'DelegationTerminal' -Value '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'
}


################################################
# Setup Hyper-V server before deploying VMs for each flavor
################################################
if ($Env:flavor -ne 'DevOps') {
    # Install and configure DHCP service (used by Hyper-V nested VMs)
    Write-Host 'Configuring DHCP Service'
    $dnsClient = Get-DnsClient | Where-Object { $_.InterfaceAlias -eq 'Ethernet' }
    $dhcpScope = Get-DhcpServerv4Scope
    if ($dhcpScope.Name -ne 'ArcBox') {
        Add-DhcpServerv4Scope -Name 'ArcBox' `
            -StartRange 10.10.1.100 `
            -EndRange 10.10.1.200 `
            -SubnetMask 255.255.255.0 `
            -LeaseDuration 1.00:00:00 `
            -State Active
    }

    $dhcpOptions = Get-DhcpServerv4OptionValue
    if ($dhcpOptions.Count -lt 3) {
        Set-DhcpServerv4OptionValue -ComputerName localhost `
            -DnsDomain $dnsClient.ConnectionSpecificSuffix `
            -DnsServer 168.63.129.16, 10.16.2.100 `
            -Router 10.10.1.1 `
            -Force
    }

    # Set custom DNS if flaver is DataOps
    if ($Env:flavor -eq 'DataOps') {
        Add-DhcpServerInDC -DnsName "$namingPrefix-client.jumpstart.local"
        Restart-Service dhcpserver
    }

    # Create the NAT network
    Write-Host 'Creating Internal NAT'
    $natName = 'InternalNat'
    $netNat = Get-NetNat
    if ($netNat.Name -ne $natName) {
        New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix 10.10.1.0/24
    }

    Write-Host 'Creating VM Credentials'
    # Hard-coded username and password for the nested VMs
    $nestedWindowsUsername = 'Administrator'
    $nestedWindowsPassword = 'JS123!!'

    # Create Windows credential object
    $secWindowsPassword = ConvertTo-SecureString $nestedWindowsPassword -AsPlainText -Force
    $winCreds = New-Object System.Management.Automation.PSCredential ($nestedWindowsUsername, $secWindowsPassword)

    # Creating Hyper-V Manager desktop shortcut
    Write-Host 'Creating Hyper-V Shortcut'
    Copy-Item -Path 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Hyper-V Manager.lnk' -Destination 'C:\Users\All Users\Desktop' -Force

    $cliDir = New-Item -Path "$Env:ArcBoxDir\.cli\" -Name '.servers' -ItemType Directory -Force
    if (-not $($cliDir.Parent.Attributes.HasFlag([System.IO.FileAttributes]::Hidden))) {
        $folder = Get-Item $cliDir.Parent.FullName -ErrorAction SilentlyContinue
        $folder.Attributes += [System.IO.FileAttributes]::Hidden
    }

    # Set Azure CLI cloud before any az commands (must happen before extensions/login)
    if ($azureEnvironment -eq 'AzureUSGovernment') {
        az cloud set --name AzureUSGovernment
    }

    # Install Azure CLI extensions
    Write-Header 'Az CLI extensions'

    az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors

    @('ssh', 'log-analytics-solution', 'connectedmachine', 'monitor-control-service') |
    ForEach-Object -Parallel {
        az extension add --name $PSItem --yes --only-show-errors
    }

    # Required for CLI commands
    Write-Header 'Az CLI Login'
    $maxRetries = 10
    $retryDelay = 30
    for ($i = 1; $i -le $maxRetries; $i++) {
        az login --identity --allow-no-subscriptions 2>&1
        if ($LASTEXITCODE -eq 0) {
            az account set -s $subscriptionId
            Write-Host "Successfully logged in to Azure CLI."
            break
        }
        Write-Host "Azure CLI login attempt $i of $maxRetries failed."
        if ($i -lt $maxRetries) {
            Write-Host "Waiting $retryDelay seconds before retrying (role assignments may still be propagating)..."
            Start-Sleep -Seconds $retryDelay
        } else {
            Write-Host "ERROR: Failed to log in to Azure CLI after $maxRetries attempts."
            Exit 1
        }
    }

    Write-Header 'Az PowerShell Login'
    $loginSucceeded = $false
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            if ($azureEnvironment -eq 'AzureUSGovernment') {
                Connect-AzAccount -Identity -Environment AzureUSGovernment -Tenant $tenantId -Subscription $subscriptionId -ErrorAction Stop
            } else {
                Connect-AzAccount -Identity -Tenant $tenantId -Subscription $subscriptionId -ErrorAction Stop
            }
            Set-AzContext -Subscription $subscriptionId -Tenant $tenantId
            $loginSucceeded = $true
            Write-Host "Successfully logged in to Azure PowerShell."
            break
        } catch {
            Write-Host "Azure PowerShell login attempt $i of $maxRetries failed: $_"
            if ($i -lt $maxRetries) {
                Write-Host "Waiting $retryDelay seconds before retrying (role assignments may still be propagating)..."
                Start-Sleep -Seconds $retryDelay
            }
        }
    }
    if (-not $loginSucceeded) {
        Write-Host "ERROR: Failed to log in to Azure PowerShell after $maxRetries attempts."
        Exit 1
    }

    # Helper function: download files from templateBaseUrl
    # Supports public GitHub raw URLs (no auth) and private Azure Blob Storage (managed identity bearer token)
    # Retries up to 15 times with exponential backoff for transient/rate-limiting failures
    function Download-ArcBoxArtifact {
        param(
            [Parameter(Mandatory)] [string]$Uri,
            [Parameter(Mandatory)] [string]$OutFile
        )
        $maxRetries = 15
        $baseDelay = 10  # Start with 10 seconds, will exponentially backoff
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                if ($Uri -match 'githubusercontent\.com') {
                    # Public GitHub raw URL - no authentication needed
                    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
                } else {
                    # Private Azure Blob Storage - use managed identity bearer token
                    $token = (Get-AzAccessToken -ResourceUrl 'https://storage.azure.com/' -AsSecureString | ForEach-Object { ConvertFrom-SecureString $_.Token -AsPlainText })
                    $headers = @{ Authorization = "Bearer $token"; 'x-ms-version' = '2020-04-08' }
                    Invoke-WebRequest -Uri $Uri -Headers $headers -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
                }
                return
            } catch {
                $fileName = Split-Path $OutFile -Leaf
                # Check if it's a 429 (Too Many Requests) or other transient error
                $is429 = $_.Exception.Message -match '429|Too Many Requests'
                if ($attempt -eq $maxRetries) {
                    Write-Warning "Download attempt $attempt/$maxRetries (final) failed for '$fileName': $($_.Exception.Message)"
                    throw
                }
                # Calculate exponential backoff: 10s, 20s, 40s, 80s, etc. (capped at 5 minutes)
                $delaySeconds = [Math]::Min($baseDelay * [Math]::Pow(2, $attempt - 1), 300)
                if ($is429) {
                    Write-Warning "Download attempt $attempt/$maxRetries failed for '$fileName' (429 Rate Limit): Waiting $delaySeconds seconds before retry..."
                } else {
                    Write-Warning "Download attempt $attempt/$maxRetries failed for '$fileName': $($_.Exception.Message) - Waiting $delaySeconds seconds..."
                }
                Start-Sleep -Seconds $delaySeconds
            }
        }
    }

    $DeploymentProgressString = 'Started ArcServersLogonScript'

    $tags = Get-AzResourceGroup -Name $env:resourceGroup | Select-Object -ExpandProperty Tags

    if ($null -ne $tags) {
        $tags['DeploymentProgress'] = $DeploymentProgressString
    } else {
        $tags = @{'DeploymentProgress' = $DeploymentProgressString }
    }

    $null = Set-AzResourceGroup -ResourceGroupName $env:resourceGroup -Tag $tags
    $null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $env:resourceGroup -ResourceType 'microsoft.compute/virtualmachines' -Tag $tags -Force

    $existingVMDisk = Get-AzDisk -ResourceGroupName $env:resourceGroup | Where-Object name -Like *VMsDisk

    # Update disk IOPS and throughput before downloading nested VMs
    az disk update --resource-group $env:resourceGroup --name $existingVMDisk.Name --disk-iops-read-write 80000 --disk-mbps-read-write 1200

    # Enable defender for cloud for SQL Server
    # Get workspace information
    $workspaceResourceID = (az monitor log-analytics workspace show --resource-group $resourceGroup --workspace-name $Env:workspaceName --query 'id' -o tsv)

    # Before deploying ArcBox SQL set resource group tag ArcSQLServerExtensionDeployment=Disabled to opt out of automatic SQL onboarding
    az tag create --resource-id "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup" --tags ArcSQLServerExtensionDeployment=Disabled

    $vhdImageToDownload = 'ArcBox-SQL-DEV.vhdx'
    if ($Env:sqlServerEdition -eq 'Standard') {
        $vhdImageToDownload = 'ArcBox-SQL-STD.vhdx'
    } elseif ($Env:sqlServerEdition -eq 'Enterprise') {
        $vhdImageToDownload = 'ArcBox-SQL-ENT.vhdx'
    }


    $DeploymentProgressString = 'Downloading and configuring nested SQL VM'

    $tags = Get-AzResourceGroup -Name $env:resourceGroup | Select-Object -ExpandProperty Tags

    if ($null -ne $tags) {
        $tags['DeploymentProgress'] = $DeploymentProgressString
    } else {
        $tags = @{'DeploymentProgress' = $DeploymentProgressString }
    }

    $null = Set-AzResourceGroup -ResourceGroupName $env:resourceGroup -Tag $tags
    $null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $env:resourceGroup -ResourceType 'microsoft.compute/virtualmachines' -Tag $tags -Force

    Write-Host 'Fetching SQL VM'
    $SQLvmName = "$namingPrefix-SQL"
    $SQLvmvhdPath = "$Env:ArcBoxVMDir\$namingPrefix-SQL.vhdx"

    # Verify if VHD files already downloaded especially when re-running this script
    if (!(Test-Path $SQLvmvhdPath)) {
        New-Item -Path $Env:ArcBoxVMDir -ItemType Directory -Force | Out-Null
        Write-Output 'Downloading nested VMs VHDX file for SQL. This can take some time, hold tight...'
        azcopy cp $vhdSourceFolder $Env:ArcBoxVMDir --include-pattern "$vhdImageToDownload" --recursive=true --check-length=false --log-level=ERROR

        # Rename VHD file
        Rename-Item -Path "$Env:ArcBoxVMDir\$vhdImageToDownload" -NewName $SQLvmvhdPath -Force
    }

    # Create the nested VMs if not already created
    Write-Header 'Create Hyper-V VMs'

    # Create the nested SQL VM using native Hyper-V cmdlets (replaces HyperVDsc DSC)
    if (-not (Get-VM -Name $SQLvmName -ErrorAction SilentlyContinue)) {
        New-VM -Name $SQLvmName -MemoryStartupBytes 6GB -VHDPath $SQLvmvhdPath -SwitchName 'InternalNATSwitch' -Generation 2 -Path 'F:\Virtual Machines'
        Set-VM -Name $SQLvmName -ProcessorCount 2
        Get-VMIntegrationService -VMName $SQLvmName -Name 'Guest Service Interface' | Enable-VMIntegrationService
        Set-VMFirmware -VMName $SQLvmName -EnableSecureBoot On
        Start-VM -Name $SQLvmName
    }

    # Restarting Windows VM Network Adapters
    Write-Host 'Restarting Network Adapters'
    Start-Sleep -Seconds 5
    try {
        # 2>&1 | Out-Null redirects the PS Direct transport-level error stream so that
        # the "OpenError: A remote session might have ended" message is suppressed from
        # the transcript. try/catch alone is insufficient because OpenError is written
        # directly to the error output stream before Invoke-Command can throw.
        Invoke-Command -VMName $SQLvmName -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCreds 2>&1 | Out-Null
    } catch {
        # Restart-NetAdapter severs the PowerShell Direct session; this OpenError is expected
    }
    Start-Sleep -Seconds 20

    # Rename server if hostname is not as ArcBox-SQL or doesn't match naming prefix
    # Wrap in try/catch: if the PS Direct session isn't fully stable after the network
    # adapter restart, Invoke-Command can throw; fall back to the current machine name.
    $hostname = $null
    try {
        $hostname = Invoke-Command -VMName $SQLvmName -ScriptBlock { hostname } -Credential $winCreds -ErrorAction SilentlyContinue 2>&1
    } catch {
        Write-Host "Could not read hostname from SQL VM (session not yet stable): $($_.Exception.Message)"
    }

    if ($hostname -ne $SQLvmName) {

        Write-Header 'Renaming the nested SQL VM'
        # Run Rename-Computer in a detached process so that the -Restart it triggers does not
        # sever the PowerShell Direct session mid-call and produce an unhandleable OpenError.
        # The separate process exits cleanly once Rename-Computer queues the restart; PS Direct
        # itself is never open when the reboot fires, so no session-teardown error is thrown.
        $renameLogPath = "$Env:ArcBoxLogsDir\SQL-Rename.log"
        $renameBlock = [scriptblock]::Create("
            Start-Transcript -Path '$renameLogPath' -Force
            Rename-Computer -NewName '$SQLvmName' -Restart -Force
            Stop-Transcript
        ")
        try {
            # 2>&1 | Out-Null suppresses the transport-level OpenError that is written to the
            # error stream before Invoke-Command can throw when the VM restarts mid-call.
            # try/catch alone is insufficient (same pattern as Restart-NetAdapter above).
            Invoke-Command -VMName $SQLvmName -ScriptBlock $renameBlock -Credential $winCreds -ErrorAction SilentlyContinue 2>&1 | Out-Null
        } catch {
            # The session is torn down by the restart before the reply can be received;
            # the OpenError here is expected and non-fatal.
            Write-Host "Rename-Computer triggered a VM restart (OpenError expected, non-fatal): $($_.Exception.Message)"
        }

        Get-VM *SQL* | Wait-VM -For IPAddress

        Write-Host 'Waiting for the nested Windows SQL VM to come back online...waiting for 30 seconds'
        Start-Sleep -Seconds 30

        # Wait for VM to start again
        while ((Get-VM -vmName $SQLvmName).State -ne 'Running') {
            Write-Host 'Waiting for VM to start...'
            Start-Sleep -Seconds 5
        }

        Write-Host 'VM has rebooted successfully!'
        Write-Host "  Rename transcript: $renameLogPath"
    }

    # Enable Windows Firewall rule for SQL Server
    Invoke-Command -VMName $SQLvmName -ScriptBlock { New-NetFirewallRule -DisplayName 'Allow SQL Server TCP 1433' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow } -Credential $winCreds

    # Download SQL assessment preparation script
    Download-ArcBoxArtifact -Uri ($Env:templateBaseUrl + 'artifacts/prepareSqlServerForAssessment.ps1') -OutFile $nestedVMArcBoxDir\prepareSqlServerForAssessment.ps1
    Copy-VMFile $SQLvmName -SourcePath "$Env:ArcBoxDir\prepareSqlServerForAssessment.ps1" -DestinationPath "$nestedVMArcBoxDir\prepareSqlServerForAssessment.ps1" -CreateFullPath -FileSource Host -Force
    Invoke-Command -VMName $SQLvmName -ScriptBlock { powershell -File $Using:nestedVMArcBoxDir\prepareSqlServerForAssessment.ps1 } -Credential $winCreds

    # Copy installation script to nested Windows VMs
    Write-Output 'Transferring installation script to nested Windows VMs...'
    Copy-VMFile $SQLvmName -SourcePath "$agentScript\installArcAgent.ps1" -DestinationPath "$Env:ArcBoxDir\installArcAgent.ps1" -CreateFullPath -FileSource Host -Force

    Write-Header 'Onboarding Arc-enabled servers'

    # Onboarding the nested VMs as Azure Arc-enabled servers
    Write-Output 'Onboarding the nested Windows VMs as Azure Arc-enabled servers'
    $accessToken = ConvertFrom-SecureString ((Get-AzAccessToken -AsSecureString).Token) -AsPlainText
    Invoke-Command -VMName $SQLvmName -ScriptBlock { powershell -File $Using:nestedVMArcBoxDir\installArcAgent.ps1 -accessToken $using:accessToken, -tenantId $Using:tenantId, -subscriptionId $Using:subscriptionId, -resourceGroup $Using:resourceGroup, -azureLocation $Using:azureLocation } -Credential $winCreds

    # Wait for the Arc-enabled server installation to be completed
    $retryCount = 0
    do {
        $ArcServer = Get-AzConnectedMachine -Name $SQLvmName -ResourceGroupName $resourceGroup
        if (($null -ne $ArcServer) -and ($ArcServer.ProvisioningState -eq 'Succeeded')) {
            Write-Host 'Onboarding the nested SQL VM as Azure Arc-enabled server successful.'
            $azConnectedMachineId = $ArcServer.Id
            break;
        } else {
            $retryCount = $retryCount + 1
            if ($retryCount -gt 5) {
                Write-Host "WARNING: Timeout exceeded for onboarding nested SQL VM as Azure Arc-enabled server ... Retry count: $retryCount."
                Exit
            } else {
                Write-Host "Waiting for onboarding nested SQL VM as Azure Arc-enabled server ... Retry count: $retryCount"
                Start-Sleep(30)
            }
        }
    } while ($retryCount -le 5)

    # Create SQL server extension as policy to auto deployment is disabled
    Write-Host "Installing SQL Server extension on the Arc-enabled Server.`n"
    az connectedmachine extension create --machine-name $SQLvmName --name 'WindowsAgent.SqlServer' --resource-group $resourceGroup --type 'WindowsAgent.SqlServer' --publisher 'Microsoft.AzureData' --settings '{\"LicenseType\":\"Paid\", \"SqlManagement\": {\"IsEnabled\":true}}' --tags $resourceTags --location $azureLocation --only-show-errors --no-wait
    Write-Host 'SQL Server extension installation on the Arc-enabled Server successful.'

    $retryCount = 0
    do {
        # Verify if Arc-enabled server and SQL server extension is installed
        $sqlExtension = Get-AzConnectedMachineExtension -ResourceGroupName $resourceGroup -MachineName $SQLvmName -Name 'WindowsAgent.SqlServer' -ErrorAction SilentlyContinue
        if ($sqlExtension -and ($sqlExtension.ProvisioningState -eq 'Succeeded')) {
            # SQL server extension is installed and ready to run SQL BPA
            Write-Host "SQL server extension is installed and ready to run SQL BPA.`n"
            break;
        } else {
            # Arc SQL Server extension is not installed or still in progress.
            $retryCount = $retryCount + 1
            if ($retryCount -gt 20) {
                Write-Warning "Timeout exceeded installing SQL server extension. Retry count: $retryCount."
            } else {
                Write-Host "Waiting for SQL server extension installation ... Retry count: $retryCount"
                Start-Sleep(30)
            }
        }
    } while ($retryCount -le 20)

    # Register Microsoft.AzureArcData provider - required for SqlServerInstances resource and migration assessment.
    # The VM managed identity has Owner at RG scope but 'register/action' requires subscription scope.
    # deploy-clientvm.ps1 pre-registers this provider from the deployer's subscription-level context,
    # so here we check first and skip if already registered; retry on transient failures.
    Write-Host "Ensuring Microsoft.AzureArcData provider is registered (required for migration assessment).`n"
    $arcDataRegistered = $false
    for ($rpRetry = 1; $rpRetry -le 5; $rpRetry++) {
        $rpState = (az provider show -n Microsoft.AzureArcData --query 'registrationState' -o tsv 2>$null)
        if ($rpState -eq 'Registered') {
            Write-Host "Microsoft.AzureArcData provider is already registered."
            $arcDataRegistered = $true
            break
        }
        Write-Host "Microsoft.AzureArcData provider state: '$rpState'. Attempting registration (attempt $rpRetry/5)..."
        $regOut = az provider register -n Microsoft.AzureArcData 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($regOut -match 'AuthorizationFailed') {
                Write-Host "WARNING: Insufficient permission to register Microsoft.AzureArcData at subscription scope."
                Write-Host "         Pre-register it from the deployer machine (deploy-clientvm.ps1 now does this automatically)."
                Write-Host "         Continuing — SqlServerInstances retry loop will wait for the provider to become available."
                break
            }
            Write-Host "Provider registration attempt $rpRetry failed: $regOut. Waiting 15 seconds..."
            Start-Sleep -Seconds 15
        } else {
            # Poll until Registered (up to 5 minutes)
            for ($poll = 1; $poll -le 20; $poll++) {
                $rpState = (az provider show -n Microsoft.AzureArcData --query 'registrationState' -o tsv 2>$null)
                if ($rpState -eq 'Registered') { $arcDataRegistered = $true; break }
                Write-Host "  Waiting for provider to become Registered (current: $rpState) ... poll $poll/20"
                Start-Sleep -Seconds 15
            }
            if ($arcDataRegistered) { break }
        }
    }
    if ($arcDataRegistered) {
        Write-Host "Microsoft.AzureArcData provider confirmed Registered."
    } else {
        Write-Host "WARNING: Could not confirm Microsoft.AzureArcData is Registered. Migration assessment may fail if the provider is not registered before SqlServerInstances is created."
    }

    # Azure Monitor Agent extension is deployed automatically using Azure Policy. Wait until extension status is Succeded.
    Write-Host "Installing Azure Monitoring Agent extension.`n"
    az connectedmachine extension create --machine-name $SQLvmName --name AzureMonitorWindowsAgent --publisher Microsoft.Azure.Monitor --type AzureMonitorWindowsAgent --resource-group $resourceGroup --location $azureLocation --only-show-errors --no-wait

    $retryCount = 0
    do {
        $amaExtension = Get-AzConnectedMachineExtension -ResourceGroupName $resourceGroup -MachineName $SQLvmName -Name 'AzureMonitorWindowsAgent' -ErrorAction SilentlyContinue
        if ($amaExtension -and ($amaExtension.ProvisioningState -eq 'Succeeded')) {
            Write-Host 'Azure Monitoring Agent extension installation complete.'
            break
        } else {
            $retryCount = $retryCount + 1
            if ($retryCount -gt 10) {
                Write-Host 'WARNING: Azure Monitor Agent extenstion is taking longger than expected. Enable SQL BPA later through Azure portal.'
                break
            } else {
                Write-Host "Waiting for Azure Monitoring Agent extension installation to complete ... Retry count: $retryCount"
                Start-Sleep(60)
            }
        }
    } while ($retryCount -le 10)

    # Re-establish Azure CLI subscription context before SQL operations (context may have been lost during nested VM operations)
    Write-Host "Re-establishing Azure CLI subscription context...`n"
    az account set --subscription $subscriptionId -ErrorAction Stop 2>&1 | Out-Null

    # Get access token to make ARM REST API call for SQL server BPA and migration assessments
    $token = (az account get-access-token --subscription $subscriptionId --query accessToken --output tsv)
    $headers = @{'Authorization' = "Bearer $token"; 'Content-Type' = 'application/json' }

    # Enable Best practices assessment
    if ($amaExtension -and ($amaExtension.ProvisioningState -eq 'Succeeded')) {

        # Create custom log analytics table for SQL assessment
        Write-Host "Creating Log Analytis workspace table for SQL best practices assessment.`n"
        az monitor log-analytics workspace table create --subscription $subscriptionId --resource-group $resourceGroup --workspace-name $Env:workspaceName -n SqlAssessment_CL --columns RawData=string TimeGenerated=datetime --only-show-errors

        # Verify if ArcBox SQL resource is created
        Write-Host "Enabling SQL server best practices assessment.`n"
        Download-ArcBoxArtifact -Uri "$Env:templateBaseUrl/artifacts/sqlbpa.json" -OutFile "$Env:ArcBoxDir\sqlbpa.json"
        az deployment group create --subscription $subscriptionId --resource-group $resourceGroup --template-file "$Env:ArcBoxDir\sqlbpa.json" --parameters workspaceName=$Env:workspaceName vmName=$SQLvmName arcSubscriptionId=$subscriptionId

        # Run Best practices assessment
        Write-Host "Execute SQL server best practices assessment.`n"

        # Wait for a minute to finish everyting and run assessment
        Start-Sleep(60)

        $armRestApiEndpoint = "${armEndpoint}/subscriptions/$subscriptionId/resourcegroups/$resourceGroup/providers/Microsoft.HybridCompute/machines/$SQLvmName/extensions/WindowsAgent.SqlServer?api-version=2019-08-02-preview"

        # Build API request payload
        $worspaceResourceId = "/subscriptions/$subscriptionId/resourcegroups/$resourceGroup/providers/microsoft.operationalinsights/workspaces/$Env:workspaceName".ToLower()
        $sqlExtensionId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.HybridCompute/machines/$SQLvmName/extensions/WindowsAgent.SqlServer"
        Download-ArcBoxArtifact -Uri "$Env:templateBaseUrl/artifacts/sqlbpa.payload.json" -OutFile "$Env:ArcBoxDir\sqlbpa.payload.json"
        $settingsSaveTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $apiPayload = (Get-Content -Path "$Env:ArcBoxDir\sqlbpa.payload.json" -Raw) -replace '{{RESOURCEID}}', $sqlExtensionId -replace '{{LOCATION}}', $azureLocation -replace '{{WORKSPACEID}}', $worspaceResourceId -replace '{{SAVETIME}}', $settingsSaveTime

        # Call REST API to run best practices assessment
        $httpResp = Invoke-WebRequest -Method Patch -Uri $armRestApiEndpoint -Body $apiPayload -Headers $headers
        if (($httpResp.StatusCode -eq 200) -or ($httpResp.StatusCode -eq 202)) {
            Write-Host 'Arc-enabled SQL server best practices assessment executed. Wait for assessment to complete to view results.'
        } else {
            <# Action when all if and elseif conditions are false #>
            Write-Host 'SQL Best Practices Assessment faild. Please refer troubleshooting guide to run manually.'
        }
    } # End of SQL BPA

    # Run SQL Server Azure Migration Assessment
    Write-Host "Enabling SQL Server Azure Migration Assessment.`n"

    # Discover the SqlServerInstances resource name created by the SQL extension.
    # IMPORTANT: The resource name is '<MachineName>_<SQLInstanceName>' (e.g. 'arcva-SQL_MSSQLSERVER'),
    # NOT the machine name alone. Query once; fall back to the conventional default-instance name
    # '<MachineName>_MSSQLSERVER' if the resource is not yet visible.
    # The migration assessment API call is best-effort — if the resource is not yet created the
    # portal will show it as pending and the user can trigger it manually.
    Write-Host "Discovering SqlServerInstances resource for machine '$SQLvmName'..."
    $sqlInstanceResourceName = $null
    $listJson = az resource list --resource-group $resourceGroup --resource-type 'Microsoft.AzureArcData/sqlServerInstances' --query "[?starts_with(name, '$SQLvmName')]" -o json 2>$null
    if ($listJson) {
        $instances = $listJson | ConvertFrom-Json
        if ($instances -and $instances.Count -gt 0) {
            $sqlInstanceResourceName = $instances[0].name
            Write-Host "  SqlServerInstances resource found: '$sqlInstanceResourceName'"
        }
    }
    if (-not $sqlInstanceResourceName) {
        # Resource not yet created by the extension — use the conventional default-instance fallback
        $sqlInstanceResourceName = "${SQLvmName}_MSSQLSERVER"
        Write-Host "  SqlServerInstances resource not yet visible; using fallback name '$sqlInstanceResourceName'."
        Write-Host "  If migration assessment fails, trigger it manually from the Azure portal once the resource appears."
        # Log all AzureArcData resources in the RG for diagnostics
        $allArcData = az resource list --resource-group $resourceGroup --resource-type 'Microsoft.AzureArcData/sqlServerInstances' -o json 2>$null
        "$(Get-Date -Format 'u') SqlServerInstances resources in RG: $allArcData" | `
            Add-Content -Path "$Env:ArcBoxLogsDir\SqlServerInstances-discovery.log" -Force
    }

    # Refresh token — the retry loop above can run for up to 15 minutes, potentially staling the token
    # obtained earlier in the script.
    $token = (az account get-access-token --subscription $subscriptionId --query accessToken --output tsv)
    $headers = @{'Authorization' = "Bearer $token"; 'Content-Type' = 'application/json' }

    $migrationApiURL = "${armEndpoint}/batch?api-version=2020-06-01"
    $assessmentName = (New-Guid).Guid
    $payLoad = @"
{"requests":[{"httpMethod":"POST","name":"$assessmentName","requestHeaderDetails":{"commandName":"Microsoft_Azure_HybridData_Platform."},"url":"${armEndpoint}/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.AzureArcData/SqlServerInstances/$sqlInstanceResourceName/runMigrationAssessment?api-version=2024-05-01-preview"}]}
"@

    $httpResp = Invoke-WebRequest -Method Post -Uri $migrationApiURL -Body $payLoad -Headers $headers
    if (($httpResp.StatusCode -eq 200) -or ($httpResp.StatusCode -eq 202)) {
        Write-Host 'Arc-enabled SQL server migration assessment executed. Wait for assessment to complete to view results.'
    } else {
        <# Action when all if and elseif conditions are false #>
        Write-Host 'SQL Server Migration Assessment faild. Please refer troubleshooting guide to run manually.'
    }

    # Install Log Analytics solutions - check first using the full resource name '{type}({workspace})'
    # to avoid CannotUpdatePlan errors when the solution was already deployed by the ARM/Bicep mgmtArtifacts template.
    # Use $LASTEXITCODE to detect existence — az monitor log-analytics solution show writes error text to stdout
    # in Azure Government, making a string-based check unreliable.
    foreach ($solutionType in @('SQLAdvancedThreatProtection', 'SQLVulnerabilityAssessment')) {
        Write-Host "Installing $solutionType Log Analytics solution.`n"
        $solutionName = "$solutionType($Env:workspaceName)"
        az monitor log-analytics solution show --resource-group $resourceGroup --name $solutionName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$solutionType Log Analytics solution already exists, skipping creation."
        } else {
            az monitor log-analytics solution create --resource-group $resourceGroup --solution-type $solutionType --workspace $Env:workspaceName --only-show-errors
        }
    }

    # Update Azure Monitor data collection rule template with Log Analytics workspace resource ID
    $sqlDefenderDcrFile = "$Env:ArcBoxDir\defendersqldcrtemplate.json"
    (Get-Content -Path $sqlDefenderDcrFile) -replace '{LOGANLYTICS_WORKSPACEID}', $workspaceResourceID | Set-Content -Path $sqlDefenderDcrFile

    # Create data collection rules for Defender for SQL
    Write-Host "Creating Azure Monitor data collection rule.`n"
    $dcrName = 'Jumpstart-DefenderForSQL-DCR'
    az monitor data-collection rule create --resource-group $resourceGroup --location $env:azureLocation --name $dcrName --rule-file $sqlDefenderDcrFile

    # Associate DCR with Azure Arc-enabled Server resource
    Write-Host "Creating Azure Monitor data collection rule assocation for Arc-enabled server.`n"
    $dcrRuleId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
    az monitor data-collection rule association create --name "$SQLvmName" --rule-id $dcrRuleId --resource $azConnectedMachineId

    # Test Defender for SQL
    Write-Header "Simulating SQL threats to generate alerts from Defender for Cloud.`n"
    $remoteScriptFileFile = "$Env:ArcBoxDir\testDefenderForSQL.ps1"
    Copy-VMFile $SQLvmName -SourcePath "$Env:ArcBoxDir\SqlAdvancedThreatProtectionShell.psm1" -DestinationPath "$Env:ArcBoxDir\SqlAdvancedThreatProtectionShell.psm1" -CreateFullPath -FileSource Host -Force
    Copy-VMFile $SQLvmName -SourcePath "$Env:ArcBoxDir\testDefenderForSQL.ps1" -DestinationPath $remoteScriptFileFile -CreateFullPath -FileSource Host -Force
    Invoke-Command -VMName $SQLvmName -ScriptBlock { powershell -File $Using:remoteScriptFileFile } -Credential $winCreds

    # Install the arcdata Azure CLI extension via wheel zip-extraction.
    # 'az extension add/update' calls pip to resolve dependencies against PyPI, which is unreachable
    # in private-endpoint Azure Government deployments (pip exits with code 2).  The confirmed
    # workaround is to download the wheel directly from the Azure CDN extension index (reachable),
    # extract it as a zip into the extension directory (bypassing pip entirely), then install any
    # missing Python dependencies one-at-a-time with 'pip install --no-deps' which reaches
    # files.pythonhosted.org even when pypi.org is blocked.
    Write-Host "Installing arcdata Azure CLI extension.`n"
    az config set extension.dynamic_install_allow_preview=true 2>&1 | Out-Null

    # ---- Locate Azure CLI bundled Python ----
    # Parse az.cmd for the embedded Python path first; fall back to well-known MSI/WinGet locations.
    $cliPythonExe = $null
    $azCmdObj     = Get-Command az -ErrorAction SilentlyContinue
    if ($azCmdObj) {
        try {
            $cmdContent = Get-Content $azCmdObj.Source -ErrorAction Stop
            foreach ($line in $cmdContent) {
                if ($line -match '"([^"]+[pP]ython[^"]*\.exe)"') {
                    $candidate = $Matches[1]
                    if (Test-Path $candidate) { $cliPythonExe = $candidate; break }
                }
            }
        } catch { }
    }
    if (-not $cliPythonExe) {
        @(
            'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe',
            'C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\python.exe',
            "$env:LOCALAPPDATA\Programs\Azure CLI\python.exe",
            "$env:ProgramFiles\Azure CLI\python.exe"
        ) | ForEach-Object { if (-not $cliPythonExe -and (Test-Path $_)) { $cliPythonExe = $_ } }
    }
    Write-Host "  CLI Python: $(if ($cliPythonExe) { $cliPythonExe } else { '(not found)' })"

    # Inject setuptools + wheel so the extension dir is importable by az.
    if ($cliPythonExe) {
        & $cliPythonExe -m pip install --quiet --disable-pip-version-check setuptools wheel 2>&1 | Out-Null
    }

    # ---- Determine extension directory ----
    # az config get extension.dir generates WARNING+ERROR noise in PS7 transcripts when the config key
    # is not set (which is the default).  The default path is always correct for ArcBox, so skip the query.
    $azExtDir = "$env:USERPROFILE\.azure\cliextensions"
    if (-not (Test-Path $azExtDir)) { New-Item -ItemType Directory -Path $azExtDir -Force | Out-Null }

    # ---- Remove any existing arcdata (stub or real) before fresh extraction ----
    az extension remove --name arcdata 2>&1 | Out-Null
    if (Test-Path "$azExtDir\arcdata") { Remove-Item "$azExtDir\arcdata" -Recurse -Force -ErrorAction SilentlyContinue }

    # ---- Resolve arcdata wheel URL from the Azure CLI extension index CDN ----
    # The CDN (azcliextensionsync.blob.core.windows.net) is reachable from within Azure even
    # with private endpoints; PyPI / GitHub may not be.
    $arcdataWheelUrl  = $null
    $arcdataWheelFile = "$env:TEMP\arcdata.whl"
    try {
        $indexJson    = (Invoke-WebRequest -Uri 'https://azcliextensionsync.blob.core.windows.net/index1/index.json' -UseBasicParsing -ErrorAction Stop).Content
        $indexObj     = $indexJson | ConvertFrom-Json
        $arcEntries   = $indexObj.extensions.arcdata
        if ($arcEntries) {
            $latest          = $arcEntries | Sort-Object { [version]($_.metadata.version) } | Select-Object -Last 1
            $arcdataWheelUrl = $latest.downloadUrl
            Write-Host "  arcdata latest: $($latest.metadata.version) — $arcdataWheelUrl"
        }
    } catch {
        Write-Warning "  Could not fetch CLI extension index: $_"
    }

    # ---- Download wheel ----
    if ($arcdataWheelUrl) {
        try {
            Invoke-WebRequest -Uri $arcdataWheelUrl -OutFile $arcdataWheelFile -UseBasicParsing -ErrorAction Stop
            Write-Host "  Wheel downloaded: $arcdataWheelFile ($('{0:N0}' -f (Get-Item $arcdataWheelFile).Length) bytes)"
        } catch {
            Write-Warning "  Wheel download failed: $_"
            $arcdataWheelFile = $null
        }
    } else {
        $arcdataWheelFile = $null
    }

    # ---- Extract wheel (zip) directly into extension dir — bypasses pip entirely ----
    $arcdataVersion = $null
    if ($arcdataWheelFile -and (Test-Path $arcdataWheelFile)) {
        try {
            $extractDir = "$azExtDir\arcdata"
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($arcdataWheelFile, $extractDir)
            $arcdataVersion = az extension show --name arcdata --query 'version' -o tsv 2>$null
            if ($arcdataVersion) {
                Write-Host "  arcdata $arcdataVersion installed via wheel extraction."
            } else {
                Write-Warning "  Wheel extracted but az extension show did not report a version."
            }
        } catch {
            Write-Warning "  Wheel extraction failed: $_"
        }
    } else {
        Write-Warning "  arcdata wheel not available — 'az sql server-arc' commands may fail."
    }

    # ---- Repair missing Python dependencies iteratively ----
    # arcdata and its transitive deps (kubernetes, durationpy, jsonpatch, etc.) are not bundled in
    # the wheel.  Install them one round at a time with 'pip install --no-deps --target' so that
    # each newly installed package's own imports are discovered in the next round.
    # files.pythonhosted.org is reachable from Azure Gov private-endpoint VMs even when pypi.org is not.
    #
    # msrestazure is a known lazy dep: azure.common.credentials imports it only when a real command
    # runs (not during --help), so the dep-repair loop never detects it.  Pre-install it explicitly.
    # IMPORTANT: --target must point to a directory that is on sys.path when az runs the extension.
    # The CLI adds <extdir>/arcdata to sys.path, so packages must land directly there (not in a
    # nested lib/ subdir).  Using --target "$azExtDir\arcdata" (the extension root) is correct;
    # however pip --no-deps with --target does not write a .pth file, so top-level package dirs
    # are importable directly from the target.  The previous version was correct in target path;
    # the real gap was that msrestazure itself depends on adal which was missing.  Install both.
    # CRITICAL: msrestazure and adal have their own transitive dependencies (msrest, azure-common,
    # requests, pycryptodome, python-dateutil, PyJWT, etc.).  Installing with --no-deps alone will
    # leave these missing, causing "import msrestazure" to fail later.  Pre-install their deps first.
    $knownLazyDepsDeps = @('msrest', 'azure-common', 'requests', 'pycryptodome', 'python-dateutil', 'PyJWT')
    $knownLazyDeps = @('msrestazure', 'adal')
    if ($arcdataVersion -and $cliPythonExe) {
        # First pass: install all transitive dependencies of the lazy deps
        foreach ($depPkg in $knownLazyDepsDeps) {
            $out = & $cliPythonExe -m pip install $depPkg --no-deps `
                       --target "$azExtDir\arcdata" --disable-pip-version-check 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [known-dep pre-install] installed transitive dep: $depPkg"
            } else {
                Write-Warning "  [known-dep pre-install] pip install $depPkg failed: $($out | Select-Object -Last 3 | Out-String)"
            }
        }
        # Second pass: install the lazy deps themselves (now that their deps are available)
        foreach ($lazyDep in $knownLazyDeps) {
            $out = & $cliPythonExe -m pip install $lazyDep --no-deps `
                       --target "$azExtDir\arcdata" --disable-pip-version-check 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [known-dep pre-install] installed $lazyDep"
            } else {
                Write-Warning "  [known-dep pre-install] pip install $lazyDep failed: $($out | Select-Object -Last 3 | Out-String)"
            }
        }
        # Verify that msrestazure is importable from the arcdata extension directory.
        # The bare Python process has no knowledge of the extension dir, so we must
        # inject it into sys.path explicitly — this mirrors what az does when it loads
        # the extension at runtime.
        $arcExtPath = "$azExtDir\arcdata".Replace('\', '\\')
        $verifyOut = & $cliPythonExe -c "import sys; sys.path.insert(0, '$arcExtPath'); import msrestazure; print(msrestazure.__version__)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  msrestazure importable from arcdata dir: $verifyOut"
        } else {
            Write-Warning "  msrestazure still not importable from arcdata dir after pre-install: $verifyOut"
            # Detailed pip show for diagnosis
            $pipLog = & $cliPythonExe -m pip show msrestazure 2>&1 | Out-String
            "$(Get-Date -Format 'u') msrestazure verify failed.`n$pipLog" | `
                Add-Content -Path "$Env:ArcBoxLogsDir\arcdata-deps.log" -Force
        }
    }
    if ($arcdataVersion -and $cliPythonExe) {
        $maxDepRounds = 12
        for ($depRound = 1; $depRound -le $maxDepRounds; $depRound++) {
            $debugOut    = & az sql server-arc --help --debug 2>&1 | Out-String
            $missingMods = [regex]::Matches($debugOut, "No module named '([^'.]+)(?:\.[^']*)?'") |
                           ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
            if (-not $missingMods) {
                Write-Host "  arcdata deps satisfied after $($depRound - 1) repair round(s)."
                break
            }
            Write-Host "  [dep-repair round $depRound] Missing: $($missingMods -join ', ')"
            $progressThisRound = $false
            foreach ($mod in $missingMods) {
                $pipPkg = $mod -replace '_', '-'
                $out    = & $cliPythonExe -m pip install $pipPkg --no-deps `
                              --target "$azExtDir\arcdata" --disable-pip-version-check 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    installed $pipPkg"
                    $progressThisRound = $true
                } else {
                    Write-Warning "    pip install $pipPkg failed (exit $($LASTEXITCODE)): $($out | Select-Object -Last 3 | Out-String)"
                }
            }
            if (-not $progressThisRound) {
                Write-Warning "  No progress in dep-repair round $depRound — stopping."
                break
            }
            if ($depRound -eq $maxDepRounds) {
                Write-Warning "  Reached max dep-repair rounds ($maxDepRounds). Some deps may still be missing."
            }
        }
        # Final verification
        $finalHelpOut = az sql server-arc --help 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "arcdata extension ready — 'az sql server-arc' loads correctly."
        } else {
            Write-Warning "arcdata installed but 'az sql server-arc --help' still fails. Check $Env:ArcBoxLogsDir for details."
        }
    }

    # Enable least privileged access and automated backups via arcdata extension.
    # az sql server-arc commands use AZURE_ENDPOINT_RESOURCE_MANAGER to determine
    # the ARM endpoint; they do NOT reliably inherit the `az cloud set` state that
    # was set earlier. Set the env var explicitly when targeting Azure Government so
    # the extension hits management.usgovcloudapi.net instead of management.azure.com.
    # Without this, arcdata sends requests to commercial Azure and gets
    # "SubscriptionNotFound" or "Could not find SQL Server" even though the resource exists.
    if ($azureEnvironment -eq 'AzureUSGovernment') {
        $env:AZURE_ENDPOINT_RESOURCE_MANAGER = 'https://management.usgovcloudapi.net/'
    }

    Write-Host "Enabling Arc-enabled SQL server least privileged access.`n"
    az sql server-arc extension feature-flag set --name LeastPrivilege --enable true --resource-group $resourceGroup --machine-name $SQLvmName --subscription $subscriptionId

    # Enable automated backups
    Write-Host "Enabling Arc-enabled SQL server automated backups.`n"
    az sql server-arc backups-policy set --name $SQLvmName --resource-group $resourceGroup --retention-days 31 --full-backup-days 7 --diff-backup-hours 12 --tlog-backup-mins 5 --subscription $subscriptionId

    # Restore env var so subsequent az commands continue using the standard cloud config
    if ($azureEnvironment -eq 'AzureUSGovernment') {
        Remove-Item Env:\AZURE_ENDPOINT_RESOURCE_MANAGER -ErrorAction SilentlyContinue
    }

    # Onboard nested Windows and Linux VMs to Azure Arc
    if ($Env:flavor -eq 'ITPro') {
        Write-Header 'Fetching Nested VMs'

        $Win2k22vmName = "$namingPrefix-Win2K22"
        $Win2k22vmvhdPath = "${Env:ArcBoxVMDir}\$namingPrefix-Win2K22.vhdx"

        $Win2k25vmName = "$namingPrefix-Win2K25"
        $Win2k25vmvhdPath = "${Env:ArcBoxVMDir}\$namingPrefix-Win2K25.vhdx"

        $Ubuntu01vmName = "$namingPrefix-Ubuntu-01"
        $Ubuntu01vmvhdPath = "${Env:ArcBoxVMDir}\$namingPrefix-Ubuntu-01.vhdx"

        $Ubuntu02vmName = "$namingPrefix-Ubuntu-02"
        $Ubuntu02vmvhdPath = "${Env:ArcBoxVMDir}\$namingPrefix-Ubuntu-02.vhdx"

        $files = 'ArcBox-Win2K22.vhdx;ArcBox-Win2K25.vhdx;ArcBox-Ubuntu-01.vhdx;ArcBox-Ubuntu-02.vhdx;'

        $DeploymentProgressString = 'Downloading and configuring nested VMs'

        $tags = Get-AzResourceGroup -Name $env:resourceGroup | Select-Object -ExpandProperty Tags

        if ($null -ne $tags) {
            $tags['DeploymentProgress'] = $DeploymentProgressString
        } else {
            $tags = @{'DeploymentProgress' = $DeploymentProgressString }
        }

        $null = Set-AzResourceGroup -ResourceGroupName $env:resourceGroup -Tag $tags
        $null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $env:resourceGroup -ResourceType 'microsoft.compute/virtualmachines' -Tag $tags -Force

        # Verify if VHD files already downloaded especially when re-running this script
        if (!((Test-Path $Win2K25vmvhdPath) -and (Test-Path $Win2k22vmvhdPath) -and (Test-Path $Ubuntu01vmvhdPath) -and (Test-Path $Ubuntu02vmvhdPath))) {
            <# Action when all if and elseif conditions are false #>
            New-Item -Path $Env:ArcBoxVMDir -ItemType Directory -Force | Out-Null
            $Env:AZCOPY_BUFFER_GB = 4
            Write-Output 'Downloading nested VMs VHDX files. This can take some time, hold tight...'
            azcopy cp $vhdSourceFolder $Env:ArcBoxVMDir --include-pattern $files --recursive=true --check-length=false --log-level=ERROR
        }

        if ($namingPrefix -ne 'ArcBox') {

            # Split the string into an array
            $fileList = $files -split ';' | Where-Object { $_ -ne '' }

            # Set the path to search for files
            $searchPath = $Env:ArcBoxVMDir

            # Loop through each file and rename if found
            foreach ($file in $fileList) {
                $filePath = Join-Path -Path $searchPath -ChildPath $file
                if (Test-Path $filePath) {
                    $newFileName = $file -replace 'ArcBox', $namingPrefix

                    Rename-Item -Path $filePath -NewName $newFileName
                    Write-Output "Renamed $file to $newFileName"
                } else {
                    Write-Output "$file not found in $searchPath"
                }
            }
        }

        # Update disk IOPS and throughput after downloading nested VMs (note: a disk's performance tier can be downgraded only once every 12 hours)
        az disk update --resource-group $env:resourceGroup --name $existingVMDisk.Name --disk-iops-read-write $existingVMDisk.DiskIOPSReadWrite --disk-mbps-read-write $existingVMDisk.DiskMBpsReadWrite

        # Create the nested VMs using native Hyper-V cmdlets (replaces HyperVDsc DSC)
        Write-Header 'Create Hyper-V VMs'

        $itproVMs = @(
            @{ Name = $Win2k22vmName; VhdPath = $Win2k22vmvhdPath; Memory = 4GB; SecureBoot = $true },
            @{ Name = $Win2k25vmName; VhdPath = $Win2k25vmvhdPath; Memory = 4GB; SecureBoot = $true },
            @{ Name = $Ubuntu01vmName; VhdPath = $Ubuntu01vmvhdPath; Memory = 4GB; SecureBoot = $false },
            @{ Name = $Ubuntu02vmName; VhdPath = $Ubuntu02vmvhdPath; Memory = 4GB; SecureBoot = $false }
        )
        foreach ($vmConfig in $itproVMs) {
            if (-not (Get-VM -Name $vmConfig.Name -ErrorAction SilentlyContinue)) {
                New-VM -Name $vmConfig.Name -MemoryStartupBytes $vmConfig.Memory -VHDPath $vmConfig.VhdPath -SwitchName 'InternalNATSwitch' -Generation 2 -Path 'F:\Virtual Machines'
                Set-VM -Name $vmConfig.Name -ProcessorCount 2
                Get-VMIntegrationService -VMName $vmConfig.Name -Name 'Guest Service Interface' | Enable-VMIntegrationService
                Set-VMFirmware -VMName $vmConfig.Name -EnableSecureBoot ($vmConfig.SecureBoot ? 'On' : 'Off')
                Start-VM -Name $vmConfig.Name
            }
        }

    # Configure automatic start & stop action for the nested VMs
    Get-VM | Where-Object {$_.State -eq "Running"} |
        ForEach-Object -Parallel {
            Stop-VM -Force -Name $PSItem.Name
            Set-VM -Name $PSItem.Name -AutomaticStopAction ShutDown -AutomaticStartAction Start
            Start-VM -Name $PSItem.Name
        }
    Start-Sleep -Seconds 30

        Write-Header 'Creating VM Credentials'
        # Hard-coded username and password for the nested VMs
        $nestedLinuxUsername = 'jumpstart'
        $nestedLinuxPassword = 'JS123!!'

        # Create Linux credential object
        $secLinuxPassword = ConvertTo-SecureString $nestedLinuxPassword -AsPlainText -Force
        $linCreds = New-Object System.Management.Automation.PSCredential ($nestedLinuxUsername, $secLinuxPassword)

        # Restarting Windows VM Network Adapters
        Write-Header 'Restarting Network Adapters'
        Start-Sleep -Seconds 5
        try {
            Invoke-Command -VMName $Win2k22vmName -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCreds
        } catch {
            # Restart-NetAdapter severs the PowerShell Direct session; this OpenError is expected
        }
        try {
            Invoke-Command -VMName $Win2k25vmName -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCreds
        } catch {
            # Restart-NetAdapter severs the PowerShell Direct session; this OpenError is expected
        }
        Start-Sleep -Seconds 10

        if ($namingPrefix -ne 'ArcBox') {

            # Renaming the nested VMs
            Write-Header 'Renaming the nested Windows VMs'
            Invoke-Command -VMName $Win2k22vmName -ScriptBlock {

                if ($env:computername -cne $using:Win2k22vmName) {
                    Rename-Computer -NewName $using:Win2k22vmName -Restart
                }

            } -Credential $winCreds

            Invoke-Command -VMName $Win2k25vmName -ScriptBlock {

                if ($env:computername -cne $using:Win2k25vmName) {
                    Rename-Computer -NewName $using:Win2k25vmName -Restart
                }

            } -Credential $winCreds

            Write-Host 'Waiting for the nested Windows VMs to come back online...'

            # Give Windows time to initiate the graceful reboot from Rename-Computer -Restart
            # before polling for the heartbeat. Do NOT call Restart-VM -Force here — that
            # hard-resets the VM while Windows is mid-shutdown, which sets the dirty-boot
            # flag and causes WinRE (automatic repair screen) on the next boot.
            Start-Sleep -Seconds 30
            Get-VM *Win* | Wait-VM -For Heartbeat


        }

        # Getting the Ubuntu nested VM IP address
        $Ubuntu01VmIp = Get-VM -Name $Ubuntu01vmName | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Select-Object -Index 0
        $Ubuntu02VmIp = Get-VM -Name $Ubuntu02vmName | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Select-Object -Index 0

        # Configuring SSH for accessing Linux VMs
        Write-Output 'Generating SSH key for accessing nested Linux VMs'

        $null = New-Item -Path ~ -Name .ssh -ItemType Directory
        ssh-keygen -t rsa -N '' -f $Env:USERPROFILE\.ssh\id_rsa

        Copy-Item -Path "$Env:USERPROFILE\.ssh\id_rsa.pub" -Destination "$Env:TEMP\authorized_keys"

        # Automatically accept unseen keys but will refuse connections for changed or invalid hostkeys.
        Add-Content -Path "$Env:USERPROFILE\.ssh\config" -Value 'StrictHostKeyChecking=accept-new'

        Get-VM *Ubuntu*  | Wait-VM -For Heartbeat
        Get-VM *Ubuntu* | Copy-VMFile -SourcePath "$Env:TEMP\authorized_keys" -DestinationPath "/home/$nestedLinuxUsername/.ssh/" -FileSource Host -Force -CreateFullPath

        if ($namingPrefix -ne 'ArcBox') {

            # Renaming the nested linux VMs
            Write-Output 'Renaming the nested Linux VMs'

            Invoke-Command -HostName $Ubuntu01VmIp -KeyFilePath "$Env:USERPROFILE\.ssh\id_rsa" -UserName $nestedLinuxUsername -ScriptBlock {

                Invoke-Expression "sudo hostnamectl set-hostname $using:ubuntu01vmName;sudo systemctl reboot"

            }

            Restart-VM -Name $ubuntu01vmName -Force

            Invoke-Command -HostName $Ubuntu02VmIp -KeyFilePath "$Env:USERPROFILE\.ssh\id_rsa" -UserName $nestedLinuxUsername -ScriptBlock {

                Invoke-Expression "sudo hostnamectl set-hostname $using:ubuntu02vmName;sudo systemctl reboot"

            }

            Restart-VM -Name $ubuntu02vmName -Force

        }

        Get-VM *Ubuntu* | Wait-VM -For IPAddress

        # Re-fetch IPs after the rename reboot — DHCP may have assigned different addresses.
        $Ubuntu01VmIp = Get-VM -Name $Ubuntu01vmName | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Select-Object -Index 0
        $Ubuntu02VmIp = Get-VM -Name $Ubuntu02vmName | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Select-Object -Index 0
        Write-Host "Ubuntu VM IPs after reboot — ${Ubuntu01vmName}: $Ubuntu01VmIp  ${Ubuntu02vmName}: $Ubuntu02VmIp"

        # Copy installation script to nested Windows VMs
        Write-Output 'Transferring installation script to nested Windows VMs...'
        Copy-VMFile $Win2k22vmName -SourcePath "$agentScript\installArcAgent.ps1" -DestinationPath "$Env:ArcBoxDir\installArcAgent.ps1" -CreateFullPath -FileSource Host -Force
        Copy-VMFile $Win2k25vmName -SourcePath "$agentScript\installArcAgent.ps1" -DestinationPath "$Env:ArcBoxDir\installArcAgent.ps1" -CreateFullPath -FileSource Host -Force

        # Update Linux VM onboarding script connect to Azure Arc, get new token as it might have been expired by the time execution reached this line.
        $accessToken = ConvertFrom-SecureString ((Get-AzAccessToken -AsSecureString).Token) -AsPlainText
        # Create per-VM installation scripts with the correct Arc resource name substituted (avoids relying on hostname inside the VM)
        $baseLinuxScript = (Get-Content -Path "$agentScript\installArcAgentUbuntu.sh" -Raw) -replace '\$accessToken', "'$accessToken'" -replace '\$resourceGroup', "'$resourceGroup'" -replace '\$tenantId', "'$Env:tenantId'" -replace '\$azureLocation', "'$Env:azureLocation'" -replace '\$subscriptionId', "'$subscriptionId'"
        $baseLinuxScript -replace '\$arcResourceName', "'$Ubuntu01vmName'" | Set-Content -Path "$agentScript\installArcAgentModifiedUbuntu01.sh"
        $baseLinuxScript -replace '\$arcResourceName', "'$Ubuntu02vmName'" | Set-Content -Path "$agentScript\installArcAgentModifiedUbuntu02.sh"

        # Deliver installation scripts to Ubuntu VMs via SSH/PowerShell remoting.
        # Copy-VMFile is NOT used here because it requires hv_fcopy_daemon inside the guest,
        # which on Ubuntu starts slowly and unreliably after a reboot. SSH is available sooner
        # and is already used by Invoke-JSSudoCommand later in this script.
        # Set-Content on Windows writes CRLF; normalise to LF so bash can execute the script.
        Write-Output 'Transferring installation script to nested Linux VMs...'
        $ubuntuDeliveries = @(
            @{ VM = $Ubuntu01vmName; IP = $Ubuntu01VmIp; Src = "$agentScript\installArcAgentModifiedUbuntu01.sh" },
            @{ VM = $Ubuntu02vmName; IP = $Ubuntu02VmIp; Src = "$agentScript\installArcAgentModifiedUbuntu02.sh" }
        )
        $destScript = "/home/$nestedLinuxUsername/installArcAgentModifiedUbuntu.sh"
        foreach ($entry in $ubuntuDeliveries) {
            $scriptContent = (Get-Content -Path $entry.Src -Raw) -replace "`r`n", "`n" -replace "`r", "`n"
            $maxSshAttempts = 20   # 20 x 15s = up to 5 minutes
            $delivered = $false
            for ($sshAttempt = 1; $sshAttempt -le $maxSshAttempts; $sshAttempt++) {
                try {
                    $ubuntuSession = New-PSSession -HostName $entry.IP -KeyFilePath "$Env:USERPROFILE\.ssh\id_rsa" -UserName $nestedLinuxUsername -ErrorAction Stop
                    Invoke-Command -Session $ubuntuSession -ScriptBlock {
                        param([string]$content, [string]$path)
                        [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
                        & chmod +x $path
                    } -ArgumentList $scriptContent, $destScript
                    Remove-PSSession $ubuntuSession -ErrorAction SilentlyContinue
                    Write-Host "  Script delivered to $($entry.VM) via SSH (attempt $sshAttempt)." -ForegroundColor Green
                    $delivered = $true
                    break
                } catch {
                    if ($sshAttempt -lt $maxSshAttempts) {
                        Write-Host "  SSH not ready on $($entry.VM) yet (attempt $sshAttempt/$maxSshAttempts). Waiting 15 seconds..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 15
                    } else {
                        Write-Warning "Could not deliver script to $($entry.VM) after $maxSshAttempts attempts. Arc onboarding will be skipped for this VM."
                    }
                }
            }
        }

        Write-Output 'Activating operating system on Windows VMs...'

        $kmsServer = if ($azureEnvironment -eq 'AzureUSGovernment') { 'kms.core.usgovcloudapi.net' } else { 'kms.core.windows.net' }

        Invoke-Command -VMName $Win2k22vmName -ScriptBlock {

            cscript C:\Windows\system32\slmgr.vbs -ipk VDYBN-27WPP-V4HQT-9VMD4-VMK7H
            cscript C:\Windows\system32\slmgr.vbs -skms $using:kmsServer
            cscript C:\Windows\system32\slmgr.vbs -ato
            cscript C:\Windows\system32\slmgr.vbs -dlv

        } -Credential $winCreds

        Invoke-Command -VMName $Win2k25vmName -ScriptBlock {

            cscript C:\Windows\system32\slmgr.vbs -ipk D764K-2NDRG-47T6Q-P8T8W-YP6DF
            cscript C:\Windows\system32\slmgr.vbs -skms $using:kmsServer
            cscript C:\Windows\system32\slmgr.vbs -ato
            cscript C:\Windows\system32\slmgr.vbs -dlv

        } -Credential $winCreds

        Write-Header 'Onboarding Arc-enabled servers'

        # Onboarding the nested VMs as Azure Arc-enabled servers
        Write-Output 'Onboarding the nested Windows VMs as Azure Arc-enabled servers'
        Invoke-Command -VMName $Win2k22vmName, $Win2k25vmName -ScriptBlock { powershell -File $Using:nestedVMArcBoxDir\installArcAgent.ps1 -accessToken $using:accessToken, -tenantId $Using:tenantId, -subscriptionId $Using:subscriptionId, -resourceGroup $Using:resourceGroup, -azureLocation $Using:azureLocation } -Credential $winCreds

        Write-Output 'Onboarding the nested Linux VMs as an Azure Arc-enabled servers'
        $UbuntuSessions = New-PSSession -HostName $Ubuntu01VmIp, $Ubuntu02VmIp -KeyFilePath "$Env:USERPROFILE\.ssh\id_rsa" -UserName $nestedLinuxUsername
        Invoke-JSSudoCommand -Session $UbuntuSessions -Command "sh /home/$nestedLinuxUsername/installArcAgentModifiedUbuntu.sh"

        Write-Header 'Installing Dependency Agent for Arc-enabled Windows servers'
        $VMs = @("$namingPrefix-SQL", "$namingPrefix-Win2K22", "$namingPrefix-Win2K25")
        $VMs | ForEach-Object -Parallel {

            $null = if ($using:azureEnvironment -eq 'AzureUSGovernment') {
                Connect-AzAccount -Identity -Scope Process -WarningAction SilentlyContinue -Environment AzureUSGovernment
                Set-AzContext -Subscription $using:subscriptionId -Tenant $using:tenantId
            } else {
                Connect-AzAccount -Identity -Tenant $using:tenantId -Subscription $using:subscriptionId -Scope Process -WarningAction SilentlyContinue
            }

            $vm = $PSItem

            Write-Output "Invoking installation on $vm"

            # Install Dependency Agent
            $null = New-AzConnectedMachineExtension -ResourceGroupName $using:resourceGroup -MachineName $vm -Name DependencyAgentWindows -Publisher Microsoft.Azure.Monitoring.DependencyAgent -ExtensionType DependencyAgentWindows -Location $using:azureLocation -Settings @{"enableAMA" = $true} -NoWait

        }

        Write-Header 'Enabling SSH access and triggering update assessment for Arc-enabled servers'
        $VMs = @("$namingPrefix-SQL", "$namingPrefix-Ubuntu-01", "$namingPrefix-Ubuntu-02", "$namingPrefix-Win2K22", "$namingPrefix-Win2K25")
        $VMs | ForEach-Object -Parallel {
            $null = if ($using:azureEnvironment -eq 'AzureUSGovernment') {
                Connect-AzAccount -Identity -Scope Process -WarningAction SilentlyContinue -Environment AzureUSGovernment
                Set-AzContext -Subscription $using:subscriptionId -Tenant $using:tenantId
            } else {
                Connect-AzAccount -Identity -Tenant $using:tenantId -Subscription $using:subscriptionId -Scope Process -WarningAction SilentlyContinue
            }

            $vm = $PSItem
            $connectedMachine = Get-AzConnectedMachine -Name $vm -ResourceGroupName $using:resourceGroup -SubscriptionId $using:subscriptionId
            $connectedMachineEndpoint = (Invoke-AzRestMethod -Method get -Path "$($connectedMachine.Id)/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15").Content | ConvertFrom-Json

            if (-not ($connectedMachineEndpoint.properties | Where-Object { $_.type -eq 'default' -and $_.provisioningState -eq 'Succeeded' })) {
                Write-Output "Creating default endpoint for $($connectedMachine.Name)"
                $null = Invoke-AzRestMethod -Method put -Path "$($connectedMachine.Id)/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15" -Payload '{"properties": {"type": "default"}}'
            }
            $connectedMachineSshEndpoint = (Invoke-AzRestMethod -Method get -Path "$($connectedMachine.Id)/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15").Content | ConvertFrom-Json

            if (-not ($connectedMachineSshEndpoint.properties | Where-Object { $_.serviceName -eq 'SSH' -and $_.provisioningState -eq 'Succeeded' })) {
                Write-Output "Enabling SSH on $($connectedMachine.Name)"
                $null = Invoke-AzRestMethod -Method put -Path "$($connectedMachine.Id)/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15" -Payload '{"properties": {"serviceName": "SSH", "port": 22}}'
            } else {
                Write-Output "SSH already enabled on $($connectedMachine.Name)"
            }

            Write-Output "Triggering Update Manager assessment on $($connectedMachine.Name)"
            $null = Invoke-AzRestMethod -Method POST -Path "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.HybridCompute/machines/$($connectedMachine.Name)/assessPatches?api-version=2020-08-15-preview" -Payload '{}'

        }
    } elseif ($Env:flavor -eq 'DataOps') {
        Write-Header 'Enabling SSH access to Arc-enabled servers'
        $null = if ($azureEnvironment -eq 'AzureUSGovernment') {
            Connect-AzAccount -Identity -Scope Process -WarningAction SilentlyContinue -Environment AzureUSGovernment
            Set-AzContext -Subscription $subscriptionId -Tenant $tenantId
        } else {
            Connect-AzAccount -Identity -Tenant $tenantId -Subscription $subscriptionId -Scope Process -WarningAction SilentlyContinue
        }
        $connectedMachine = Get-AzConnectedMachine -Name $SQLvmName -ResourceGroupName $resourceGroup -SubscriptionId $subscriptionId
        $connectedMachineEndpoint = (Invoke-AzRestMethod -Method get -Path "$($connectedMachine.Id)/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15").Content | ConvertFrom-Json
        if (-not ($connectedMachineEndpoint.properties | Where-Object { $_.type -eq 'default' -and $_.provisioningState -eq 'Succeeded' })) {
            Write-Output "Creating default endpoint for $($connectedMachine.Name)"
            $null = Invoke-AzRestMethod -Method put -Path "$($connectedMachine.Id)/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15" -Payload '{"properties": {"type": "default"}}'
        }

        $connectedMachineSshEndpoint = (Invoke-AzRestMethod -Method get -Path "$($connectedMachine.Id)/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15").Content | ConvertFrom-Json
        if (-not ($connectedMachineSshEndpoint.properties | Where-Object { $_.serviceName -eq 'SSH' -and $_.provisioningState -eq 'Succeeded' })) {
            Write-Output "Enabling SSH on $($connectedMachine.Name)"
            $null = Invoke-AzRestMethod -Method put -Path "$($connectedMachine.Id)/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15" -Payload '{"properties": {"serviceName": "SSH", "port": 22}}'
        } else {
            Write-Output "SSH already enabled on $($connectedMachine.Name)"
        }

        Write-Output "Triggering Update Manager assessment on $($connectedMachine.Name)"
        $null = Invoke-AzRestMethod -Method POST -Path "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.HybridCompute/machines/$($connectedMachine.Name)/assessPatches?api-version=2020-08-15-preview" -Payload '{}'

    }

    # Removing the LogonScript Scheduled Task so it won't run on next reboot
    Write-Header 'Removing Logon Task'
    if ($null -ne (Get-ScheduledTask -TaskName 'ArcServersLogonScript' -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName 'ArcServersLogonScript' -Confirm:$false
    }
}

# Triggering Azure Policy compliance scan
Write-Header 'Triggering Azure Policy compliance scan'
try {
    Import-Module Az.PolicyInsights -ErrorAction Stop
    Start-AzPolicyComplianceScan -ResourceGroupName $resourceGroup -AsJob
    Write-Host 'Azure Policy compliance scan triggered via Az.PolicyInsights module.'
} catch {
    # Az.PolicyInsights not installed — fall back to REST API.
    # Invoke-AzRestMethod -Path uses the ARM base URL from the current Az context,
    # which is already set to AzureUSGovernment (management.usgovcloudapi.net).
    Write-Host 'Az.PolicyInsights module not available, triggering policy compliance scan via REST API.'
    $policyResult = Invoke-AzRestMethod -Method POST -Path "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.PolicyInsights/policyStates/latest/triggerEvaluation?api-version=2019-10-01" -ErrorAction SilentlyContinue
    if ($null -eq $policyResult) {
        Write-Host 'WARNING: Policy compliance scan REST call returned no response (possible auth or endpoint issue).' -ForegroundColor Yellow
    } elseif ($policyResult.StatusCode -in 200, 202) {
        Write-Host "Azure Policy compliance scan triggered successfully (HTTP $($policyResult.StatusCode))."
    } else {
        Write-Host "WARNING: Policy compliance scan returned HTTP $($policyResult.StatusCode): $($policyResult.Content)" -ForegroundColor Yellow
    }
}

#Changing to Jumpstart ArcBox wallpaper
Write-Header 'Changing wallpaper'

# Allow wallpaper in RDP/Bastion sessions. Azure Bastion and mstsc with bandwidth-saving
# profiles set fDisableWallpaper=1 on the RDP-Tcp listener at connection time, causing
# Explorer to suppress wallpaper rendering even when SPI_SETDESKWALLPAPER succeeds server-side.
$winStationPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
if (Test-Path $winStationPath) {
    Set-ItemProperty -Path $winStationPath -Name 'fDisableWallpaper' -Value 0 -Type DWord -Force
    Write-Host "Set RDP-Tcp fDisableWallpaper=0 — wallpaper enabled for RDP/Bastion sessions."
}

# Convert wallpaper PNG to BMP (compositing onto black to remove alpha channel) and apply
$wallpaperPng = "$Env:ArcBoxDir\wallpaper.png"
$wallpaperBmp = "$Env:ArcBoxDir\wallpaper.bmp"
if (Test-Path $wallpaperPng) {
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $img = [System.Drawing.Image]::FromFile($wallpaperPng)
        $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.DrawImage($img, 0, 0, $img.Width, $img.Height)
        $g.Dispose()
        $bmp.Save($wallpaperBmp, [System.Drawing.Imaging.ImageFormat]::Bmp)
        $img.Dispose(); $bmp.Dispose()
        Write-Host "Wallpaper BMP created: $wallpaperBmp"
    } catch {
        Write-Warning "PNG to BMP conversion failed: $_"
    }
}

if (Test-Path $wallpaperBmp) {
    # Point HKCU at wallpaper.bmp
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper'      -Value $wallpaperBmp -Force
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10'           -Force
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper'  -Value '0'            -Force

    # BGInfo reads WallpaperSource (not HKCU\Control Panel\Desktop\Wallpaper) as its base image.
    # Set it before BGInfo runs so it composites on the ArcBox image, not the Windows default.
    $ieDesktopKey = 'HKCU:\Software\Microsoft\Internet Explorer\Desktop\General'
    if (-not (Test-Path $ieDesktopKey)) { New-Item -Path $ieDesktopKey -Force | Out-Null }
    Set-ItemProperty -Path $ieDesktopKey -Name 'WallpaperSource' -Value $wallpaperBmp -Force
}

if ($Env:flavor -eq 'ITPro') {

    Write-Header 'Running tests to verify infrastructure'

    & "$Env:ArcBoxTestsDir\Invoke-Test.ps1"

}