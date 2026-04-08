param (
    [string]$adminUsername,
    [string]$spnClientId,
    [string]$tenantId,
    [string]$spnAuthority,
    [string]$subscriptionId,
    [string]$resourceGroup,
    [string]$azdataUsername,
    [string]$acceptEula,
    [string]$registryUsername,
    [string]$arcDcName,
    [string]$azureLocation,
    [string]$mssqlmiName,
    [string]$POSTGRES_NAME,
    [string]$POSTGRES_WORKER_NODE_COUNT,
    [string]$POSTGRES_DATASIZE,
    [string]$POSTGRES_SERVICE_TYPE,
    [string]$stagingStorageAccountName,
    [string]$workspaceName,
    [string]$k3sArcDataClusterName,
    [string]$k3sArcClusterName,
    [string]$aksArcClusterName,
    [string]$aksdrArcClusterName,
    [string]$githubBranch,
    [string]$githubUser,
    [string]$templateBaseUrl,
    [string]$flavor,
    [string]$rdpPort,
    [string]$sshPort,
    [string]$vmAutologon,
    [string]$addsDomainName,
    [string]$customLocationRPOID,
    [object]$resourceTags,
    [string]$namingPrefix,
    [string]$debugEnabled,
    [string]$sqlServerEdition,
    [string]$autoShutdownEnabled,
    [string]$azureEnvironment = 'AzureCloud',
    [string]$keyVaultName = ''
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnAuthority', $spnAuthority, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('tenantId', $tenantId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AZDATA_USERNAME', $azdataUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('ACCEPT_EULA', $acceptEula, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('registryUsername', $registryUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('arcDcName', $arcDcName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('subscriptionId', $subscriptionId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('mssqlmiName', $mssqlmiName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_NAME', $POSTGRES_NAME, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_WORKER_NODE_COUNT', $POSTGRES_WORKER_NODE_COUNT, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_DATASIZE', $POSTGRES_DATASIZE, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_SERVICE_TYPE', $POSTGRES_SERVICE_TYPE, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('stagingStorageAccountName', $stagingStorageAccountName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('workspaceName', $workspaceName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('k3sArcDataClusterName', $k3sArcDataClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('k3sArcClusterName', $k3sArcClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('githubBranch', $githubBranch, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('githubUser', $githubUser, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', $templateBaseUrl, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('flavor', $flavor, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('automationTriggerAtLogon', $automationTriggerAtLogon, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('addsDomainName', $addsDomainName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('aksArcClusterName', $aksArcClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('aksdrArcClusterName', $aksdrArcClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('customLocationRPOID', $customLocationRPOID, [System.EnvironmentVariableTarget]::Machine)
# Serialize resourceTags as 'key=value' pairs for Azure CLI compatibility (avoids 'System.Collections.Hashtable' being stored)
$resourceTagsStr = if ($resourceTags -is [hashtable]) { ($resourceTags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ' } else { [string]$resourceTags }
[System.Environment]::SetEnvironmentVariable('resourceTags', $resourceTagsStr, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('namingPrefix', $namingPrefix, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('ArcBoxDir', "C:\ArcBox", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('sqlServerEdition', $sqlServerEdition, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('autoShutdownEnabled', $autoShutdownEnabled, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureEnvironment', $azureEnvironment, [System.EnvironmentVariableTarget]::Machine)

if ($debugEnabled -eq "true") {
    [System.Environment]::SetEnvironmentVariable('ErrorActionPreference', "Break", [System.EnvironmentVariableTarget]::Machine)
} else {
    [System.Environment]::SetEnvironmentVariable('ErrorActionPreference', "Continue", [System.EnvironmentVariableTarget]::Machine)
}

# Formatting VMs disk
$disk = (Get-Disk | Where-Object partitionstyle -eq 'raw')[0]
$driveLetter = "F"
$label = "VMsDisk"
$disk | Initialize-Disk -PartitionStyle MBR -PassThru | `
    New-Partition -UseMaximumSize -DriveLetter $driveLetter | `
    Format-Volume -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false -Force

# Creating ArcBox path
Write-Output "Creating ArcBox path"
$Env:ArcBoxDir = "C:\ArcBox"
$Env:ArcBoxDscDir = "$Env:ArcBoxDir\DSC"
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$Env:ArcBoxVMDir = "F:\Virtual Machines"
$Env:ArcBoxKVDir = "$Env:ArcBoxDir\KeyVault"
$Env:ArcBoxGitOpsDir = "$Env:ArcBoxDir\GitOps"
$Env:ArcBoxIconDir = "$Env:ArcBoxDir\Icons"
$Env:agentScript = "$Env:ArcBoxDir\agentScript"
$Env:ArcBoxTestsDir = "$Env:ArcBoxDir\Tests"
$Env:ToolsDir = "C:\Tools"
$Env:tempDir = "C:\Temp"
$Env:ArcBoxDataOpsDir = "$Env:ArcBoxDir\DataOps"

New-Item -Path $Env:ArcBoxDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxDscDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxLogsDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxVMDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxKVDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxGitOpsDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxIconDir -ItemType directory -Force
New-Item -Path $Env:ToolsDir -ItemType Directory -Force
New-Item -Path $Env:tempDir -ItemType directory -Force
New-Item -Path $Env:agentScript -ItemType directory -Force
New-Item -Path $Env:ArcBoxDataOpsDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxTestsDir -ItemType directory -Force

Start-Transcript -Path $Env:ArcBoxLogsDir\Bootstrap.log

# SyncForegroundPolicy=1 makes Windows wait for GP sync before completing logon.
# Only DataOps needs this (domain join + GP propagation). ITPro is non-domain: setting
# it to 1 causes autologon to stall waiting for a domain controller that doesn't exist,
# which delays or blocks the AtLogOn scheduled tasks (WinGetLogonScript, ArcServersLogonScript).
if ($flavor -eq "DataOps") {
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "SyncForegroundPolicy" 1
} else {
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "SyncForegroundPolicy" 0
}

# Note: PSProfile.ps1 download moved to after Az login (requires MI auth for private blob storage)

# Extending C:\ partition to the maximum size
Write-Host "Extending C:\ partition to the maximum size"
Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax

# Installing PowerShell Modules
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Trust PSGallery before installing modules. On WS2019 the default PowerShellGet 1.0.0.1
# ships with PSGallery set to Untrusted, which causes Install-Module to silently fail with
# 'No match found' even when the module exists. Trusting it first resolves the issue.
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Install-Module -Name Microsoft.PowerShell.PSResourceGet -Force -AllowClobber

# Pin Az-modules after other modules to avoid version conflicts
# See: https://github.com/microsoft/azure_arc/issues/3359
Install-PSResource -Name Az.Accounts -Version 5.3.1 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Az.KeyVault -Version 6.4.1 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Az.Compute -Version 11.1.0 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Az.Resources -Version 9.0.0 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Az.Storage -Version 9.4.0  -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Microsoft.PowerShell.SecretManagement -Version 1.1.2 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall

# Import the module to ensure the correct version is loaded
Import-Module Az.Accounts -RequiredVersion 5.3.1 -Force
Import-Module Az.KeyVault -RequiredVersion 6.4.1 -Force
Import-Module Az.Resources -RequiredVersion 9.0.0 -Force

$DeploymentProgressString = "Started bootstrap-script..."

# Set Azure cloud environment for Azure Government (only if az CLI is already installed)
if ($azureEnvironment -eq 'AzureUSGovernment') {
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if ($azCmd) {
        az cloud set --name AzureUSGovernment
    } else {
        Write-Host "az CLI not yet installed - skipping 'az cloud set'. Will be configured in logon scripts."
    }
}

# Connect via managed identity with retries (MI may take time to become available)
$miConnected = $false
for ($miAttempt = 1; $miAttempt -le 20; $miAttempt++) {
    try {
        Write-Host "Connect-AzAccount -Identity attempt $miAttempt of 20..."
        if ($azureEnvironment -eq 'AzureUSGovernment') {
            Connect-AzAccount -Identity -Environment AzureUSGovernment -ErrorAction Stop
        } else {
            Connect-AzAccount -Identity -ErrorAction Stop
        }
        $miConnected = $true
        Write-Host "Managed identity authentication succeeded." -ForegroundColor Green
        break
    } catch {
        Write-Warning "MI auth attempt $miAttempt failed: $($_.Exception.Message)"
        if ($miAttempt -eq 20) {
            Write-Error "FATAL: Connect-AzAccount -Identity failed after 20 attempts. Cannot proceed."
            Stop-Transcript
            exit 1
        }
        Start-Sleep -Seconds 30
    }
}

# Helper function: download files from templateBaseUrl
# Supports public GitHub raw URLs (no auth) and private Azure Blob Storage (managed identity bearer token)
# Retries up to 10 times (30s intervals) to handle transient failures
function Download-ArcBoxArtifact {
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [string]$OutFile
    )
    $maxRetries = 10
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
            Write-Warning "Download attempt $attempt/$maxRetries failed for '$fileName': $($_.Exception.Message)"
            if ($attempt -eq $maxRetries) {
                Write-Error "FATAL: Failed to download '$fileName' from '$Uri' after $maxRetries attempts."
                throw
            }
            Start-Sleep -Seconds 30
        }
    }
}

# Track download failures
$script:downloadErrors = @()

# Download PSProfile now that MI auth is available
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/PSProfile.ps1") -OutFile $PsHome\Profile.ps1
.$PsHome\Profile.ps1

$tags = Get-AzResourceGroup -Name $resourceGroup | Select-Object -ExpandProperty Tags

if ($null -ne $tags) {
    $tags["DeploymentProgress"] = $DeploymentProgressString
} else {
    $tags = @{"DeploymentProgress" = $DeploymentProgressString}
}

$null = Set-AzResourceGroup -ResourceGroupName $resourceGroup -Tag $tags

# Resolve Key Vault object.
# The Key Vault name is passed in directly from the Bicep deployment (deterministic uniqueString)
# so we do a targeted Get-AzKeyVault -VaultName lookup instead of an RBAC-gated list call.
# This avoids the race condition where Get-AzKeyVault -ResourceGroupName returns empty while
# RBAC role assignments are still propagating (which can exceed 10 min in Azure Government).
# Fall back to resource-group enumeration with retries if the parameter was not provided.
if ($keyVaultName) {
    Write-Host "Key Vault name provided by deployment: '$keyVaultName'. Looking up vault object..."
    $KeyVault = $null
    for ($kvRetry = 1; $kvRetry -le 20; $kvRetry++) {
        $KeyVault = Get-AzKeyVault -VaultName $keyVaultName -ErrorAction SilentlyContinue
        if ($KeyVault) {
            Write-Host "Key Vault found: $($KeyVault.VaultName) (attempt $kvRetry)"
            break
        }
        Write-Warning "Get-AzKeyVault -VaultName '$keyVaultName' returned null (attempt $kvRetry/20). Retrying in 30s..."
        if ($kvRetry -eq 20) {
            Write-Error "FATAL: Get-AzKeyVault -VaultName '$keyVaultName' failed after 20 attempts. Cannot retrieve windowsAdminPassword."
            Stop-Transcript
            exit 1
        }
        Start-Sleep -Seconds 30
        if ($azureEnvironment -eq 'AzureUSGovernment') {
            Connect-AzAccount -Identity -Environment AzureUSGovernment -ErrorAction SilentlyContinue | Out-Null
        } else {
            Connect-AzAccount -Identity -ErrorAction SilentlyContinue | Out-Null
        }
    }
} else {
    Write-Warning "keyVaultName parameter not provided. Falling back to Get-AzKeyVault -ResourceGroupName (RBAC propagation may cause delays)."
    $KeyVault = $null
    for ($kvRetry = 1; $kvRetry -le 20; $kvRetry++) {
        $KeyVault = Get-AzKeyVault -ResourceGroupName $resourceGroup
        if ($KeyVault) {
            Write-Host "Key Vault found: $($KeyVault.VaultName) (attempt $kvRetry)"
            break
        }
        Write-Warning "Key Vault not found in resource group '$resourceGroup' (attempt $kvRetry/20). Retrying in 30s..."
        if ($kvRetry -eq 20) {
            Write-Error "FATAL: Key Vault not found in resource group '$resourceGroup' after 20 attempts. Cannot retrieve windowsAdminPassword."
            Stop-Transcript
            exit 1
        }
        Start-Sleep -Seconds 30
        if ($azureEnvironment -eq 'AzureUSGovernment') {
            Connect-AzAccount -Identity -Environment AzureUSGovernment -ErrorAction SilentlyContinue | Out-Null
        } else {
            Connect-AzAccount -Identity -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

# Set Key Vault Name as an environment variable (used by DevOps flavor)
[System.Environment]::SetEnvironmentVariable('keyVaultName', $KeyVault.VaultName, [System.EnvironmentVariableTarget]::Machine)

# Import required module
Import-Module Microsoft.PowerShell.SecretManagement

# Register the Azure Key Vault as a secret vault if not already registered
# Ensure you have installed the SecretManagement and SecretStore modules along with the Key Vault extension

if (-not (Get-SecretVault -Name $KeyVault.VaultName -ErrorAction Ignore)) {
    # Pass VaultName (not VaultUri) to AZKVaultName. The Az.KeyVault SecretManagement adapter
    # passes this value directly to Get-AzKeyVaultSecret -VaultName, which constructs the
    # correct endpoint URL from the current Az context environment (AzureUSGovernment here).
    # Passing the full VaultUri causes the adapter to double-construct a URL like
    # 'https://https://vault.vault.usgovcloudapi.net...' which fails with "Invalid URI: The
    # hostname could not be parsed."
    Register-SecretVault -Name $KeyVault.VaultName -ModuleName Az.KeyVault -VaultParameters @{ AZKVaultName = $KeyVault.VaultName } -DefaultVault
}

$adminPassword = Get-Secret -Name windowsAdminPassword -AsPlainText

if ($vmAutologon -eq "true") {

    Write-Host "Configuring VM Autologon"

    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "AutoAdminLogon" "1"
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "DefaultUserName" $adminUsername
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "DefaultPassword" $adminPassword
    if($flavor -eq "DataOps"){
        Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "DefaultDomainName" "jumpstart.local"
    }
} else {

    Write-Host "Not configuring VM Autologon"

}

# Temporarily disabling Azure VM Auto-shutdown while automation is in progress
if ($autoShutdownEnabled -eq "true") {

    $ScheduleResource = Get-AzResource -ResourceGroup $resourceGroup -ResourceType Microsoft.DevTestLab/schedules
    $armEndpoint = if ($azureEnvironment -eq 'AzureUSGovernment') { 'https://management.usgovcloudapi.net' } else { 'https://management.azure.com' }
    $Uri = "${armEndpoint}$($ScheduleResource.ResourceId)?api-version=2018-09-15"

    $Schedule = Invoke-AzRestMethod -Uri $Uri

    $ScheduleSettings = $Schedule.Content | ConvertFrom-Json
    $ScheduleSettings.properties.status = "Disabled"

    Invoke-AzRestMethod -Uri $Uri -Method PUT -Payload ($ScheduleSettings | ConvertTo-Json -Depth 5)

}

# Installing tools and module

Write-Header "Installing PowerShell 7"

$ProgressPreference = 'SilentlyContinue'
$url = "https://github.com/PowerShell/PowerShell/releases/latest"
$latestVersion = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content | Select-String -Pattern "v[0-9]+\.[0-9]+\.[0-9]+" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value
$downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/$latestVersion/PowerShell-$($latestVersion.Substring(1,5))-win-x64.msi"
Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile .\PowerShell7.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I PowerShell7.msi /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1'
Remove-Item .\PowerShell7.msi

Copy-Item $PsHome\Profile.ps1 -Destination "C:\Program Files\PowerShell\7\"


$modules = @("Az.ConnectedMachine", "Az.ConnectedKubernetes", "Az.CustomLocation", "Az.PolicyInsights", "Azure.Arc.Jumpstart.Common", "Pester")

foreach ($module in $modules) {
    Install-PSResource -Name $module -Scope AllUsers -Quiet -AcceptLicense -TrustRepository
}

Write-Header "Fetching GitHub Artifacts"

# All flavors
Write-Host "Fetching Artifacts for All Flavors"
Invoke-WebRequest "https://raw.githubusercontent.com/Azure/arc_jumpstart_docs/main/img/wallpaper/arcbox_wallpaper_dark.png" -OutFile $Env:ArcBoxDir\wallpaper.png
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/MonitorWorkbookLogonScript.ps1") -OutFile $Env:ArcBoxDir\MonitorWorkbookLogonScript.ps1
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/mgmtMonitorWorkbook.parameters.json") -OutFile $Env:ArcBoxDir\mgmtMonitorWorkbook.parameters.json
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/monitoring/arc-inventory-workbook.json") -OutFile "$Env:ArcBoxDir\arc-inventory-workbook.json"
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/monitoring/arc-osperformance-workbook.json") -OutFile "$Env:ArcBoxDir\arc-osperformance-workbook.json"
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/DeploymentStatus.ps1") -OutFile $Env:ArcBoxDir\DeploymentStatus.ps1
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/LogInstructions.txt") -OutFile $Env:ArcBoxLogsDir\LogInstructions.txt
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/dsc/common.dsc.yml") -OutFile $Env:ArcBoxDscDir\common.dsc.yml
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/dsc/virtual_machines_sql.dsc.yml") -OutFile $Env:ArcBoxDscDir\virtual_machines_sql.dsc.yml
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/tests/arcbox-bginfo.bgi") -OutFile $Env:ArcBoxTestsDir\arcbox-bginfo.bgi
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/tests/common.tests.ps1") -OutFile $Env:ArcBoxTestsDir\common.tests.ps1
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/tests/Invoke-Test.ps1") -OutFile $Env:ArcBoxTestsDir\Invoke-Test.ps1
Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/WinGet.ps1") -OutFile $Env:ArcBoxDir\WinGet.ps1

# Workbook template
if ($flavor -eq "ITPro") {
    Write-Host "Fetching Workbook Template Artifact for ITPro"
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/mgmtMonitorWorkbookITPro.json") -OutFile $Env:ArcBoxDir\mgmtMonitorWorkbook.json
}
elseif ($flavor -eq "DevOps") {
    Write-Host "Fetching Workbook Template Artifact for DevOps"
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/mgmtMonitorWorkbookDevOps.json") -OutFile $Env:ArcBoxDir\mgmtMonitorWorkbook.json
}
elseif ($flavor -eq "DataOps") {
    Write-Host "Fetching Workbook Template Artifact for DataOps"
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/mgmtMonitorWorkbookDataOps.json") -OutFile $Env:ArcBoxDir\mgmtMonitorWorkbook.json
}

# ITPro
if ($flavor -eq "ITPro") {
    Write-Host "Fetching Artifacts for ITPro Flavor"
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/ArcServersLogonScript.ps1") -OutFile $Env:ArcBoxDir\ArcServersLogonScript.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/installArcAgent.ps1") -OutFile $Env:ArcBoxDir\agentScript\installArcAgent.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/installArcAgentUbuntu.sh") -OutFile $Env:ArcBoxDir\agentScript\installArcAgentUbuntu.sh
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/icons/arcsql.ico") -OutFile $Env:ArcBoxIconDir\arcsql.ico
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/installArcAgentSQLUser.ps1") -OutFile $Env:ArcBoxDir\installArcAgentSQLUser.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/SqlAdvancedThreatProtectionShell.psm1") -OutFile $Env:ArcBoxDir\SqlAdvancedThreatProtectionShell.psm1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/defendersqldcrtemplate.json") -OutFile $Env:ArcBoxDir\defendersqldcrtemplate.json
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/testDefenderForSQL.ps1") -OutFile $Env:ArcBoxDir\testDefenderForSQL.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/tests/itpro.tests.ps1") -OutFile $Env:ArcBoxTestsDir\itpro.tests.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/dsc/itpro.dsc.yml") -OutFile $Env:ArcBoxDscDir\itpro.dsc.yml
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/dsc/virtual_machines_itpro.dsc.yml") -OutFile $Env:ArcBoxDscDir\virtual_machines_itpro.dsc.yml
}

# DevOps
if ($flavor -eq "DevOps") {
    Write-Host "Fetching Artifacts for DevOps Flavor"
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/DevOpsLogonScript.ps1") -OutFile $Env:ArcBoxDir\DevOpsLogonScript.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/BookStoreLaunch.ps1") -OutFile $Env:ArcBoxDir\BookStoreLaunch.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/devops_ingress/bookbuyer.yaml") -OutFile $Env:ArcBoxKVDir\bookbuyer.yaml
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/devops_ingress/bookstore.yaml") -OutFile $Env:ArcBoxKVDir\bookstore.yaml
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/devops_ingress/hello-arc.yaml") -OutFile $Env:ArcBoxKVDir\hello-arc.yaml
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/gitops_scripts/K3sGitOps.ps1") -OutFile $Env:ArcBoxGitOpsDir\K3sGitOps.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/gitops_scripts/K3sRBAC.ps1") -OutFile $Env:ArcBoxGitOpsDir\K3sRBAC.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/icons/arc.ico") -OutFile $Env:ArcBoxIconDir\arc.ico
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/icons/bookstore.ico") -OutFile $Env:ArcBoxIconDir\bookstore.ico
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/tests/devops.tests.ps1") -OutFile $Env:ArcBoxTestsDir\devops.tests.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/dsc/devops.dsc.yml") -OutFile $Env:ArcBoxDscDir\devops.dsc.yml
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/longhorn.yaml") -OutFile $Env:ArcBoxDir\longhorn.yaml
}

# DataOps
if ($flavor -eq "DataOps") {
    Write-Host "Fetching Artifacts for DataOps Flavor"
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/ArcServersLogonScript.ps1") -OutFile $Env:ArcBoxDir\ArcServersLogonScript.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/DataOpsLogonScript.ps1") -OutFile $Env:ArcBoxDir\DataOpsLogonScript.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/RunAfterClientVMADJoin.ps1") -OutFile $Env:ArcBoxDir\RunAfterClientVMADJoin.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/settingsTemplate.json") -OutFile $Env:ArcBoxDir\settingsTemplate.json
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/DeploySQLMIADAuth.ps1") -OutFile $Env:ArcBoxDir\DeploySQLMIADAuth.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/dataController.json") -OutFile $Env:ArcBoxDir\dataController.json
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/dataController.parameters.json") -OutFile $Env:ArcBoxDir\dataController.parameters.json
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/sqlmiAD.json") -OutFile $Env:ArcBoxDir\sqlmiAD.json
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/sqlmiAD.parameters.json") -OutFile $Env:ArcBoxDir\sqlmiAD.parameters.json
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/SQLMIEndpoints.ps1") -OutFile $Env:ArcBoxDir\SQLMIEndpoints.ps1
    Invoke-WebRequest "https://github.com/ErikEJ/SqlQueryStress/releases/download/0.9.7.166/SqlQueryStress.exe" -OutFile $Env:ArcBoxDir\SqlQueryStress.exe
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/adConnector.json") -OutFile $Env:ArcBoxDir\adConnector.json
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/adConnector.parameters.json") -OutFile $Env:ArcBoxDir\adConnector.parameters.json
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/DataOpsAppScript.ps1") -OutFile $Env:ArcBoxDir\DataOpsAppScript.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/icons/bookstore.ico") -OutFile $Env:ArcBoxIconDir\bookstore.ico
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/DataOpsAppDRScript.ps1") -OutFile $Env:ArcBoxDataOpsDir\DataOpsAppDRScript.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/DataOpsTestAppScript.ps1") -OutFile $Env:ArcBoxDataOpsDir\DataOpsTestAppScript.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/installArcAgent.ps1") -OutFile $Env:ArcBoxDir\agentScript\installArcAgent.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/SqlAdvancedThreatProtectionShell.psm1") -OutFile $Env:ArcBoxDir\SqlAdvancedThreatProtectionShell.psm1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/defendersqldcrtemplate.json") -OutFile $Env:ArcBoxDir\defendersqldcrtemplate.json
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/testDefenderForSQL.ps1") -OutFile $Env:ArcBoxDir\testDefenderForSQL.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/tests/dataops.tests.ps1") -OutFile $Env:ArcBoxTestsDir\dataops.tests.ps1
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/dsc/dataops.dsc.yml") -OutFile $Env:ArcBoxDscDir\dataops.dsc.yml
    Download-ArcBoxArtifact -Uri ($templateBaseUrl + "artifacts/longhorn.yaml") -OutFile $Env:ArcBoxDir\longhorn.yaml
}

# -------------------------------------------------------------------
# Verification gate: confirm all critical files were downloaded
# If any required file is missing, stop the script immediately.
# -------------------------------------------------------------------
Write-Header "Verifying artifact downloads from storage account"

$requiredFiles = @(
    "$Env:ArcBoxDir\WinGet.ps1",
    "$Env:ArcBoxDir\DeploymentStatus.ps1",
    "$Env:ArcBoxDir\MonitorWorkbookLogonScript.ps1",
    "$Env:ArcBoxDir\mgmtMonitorWorkbook.parameters.json",
    "$Env:ArcBoxDir\mgmtMonitorWorkbook.json"
)

if ($flavor -eq "ITPro") {
    $requiredFiles += @(
        "$Env:ArcBoxDir\ArcServersLogonScript.ps1",
        "$Env:ArcBoxDir\agentScript\installArcAgent.ps1",
        "$Env:ArcBoxDir\agentScript\installArcAgentUbuntu.sh",
        "$Env:ArcBoxDir\installArcAgentSQLUser.ps1",
        "$Env:ArcBoxDir\defendersqldcrtemplate.json"
    )
}
if ($flavor -eq "DevOps") {
    $requiredFiles += @(
        "$Env:ArcBoxDir\DevOpsLogonScript.ps1",
        "$Env:ArcBoxDir\BookStoreLaunch.ps1"
    )
}
if ($flavor -eq "DataOps") {
    $requiredFiles += @(
        "$Env:ArcBoxDir\ArcServersLogonScript.ps1",
        "$Env:ArcBoxDir\DataOpsLogonScript.ps1",
        "$Env:ArcBoxDir\dataController.json"
    )
}

$missingFiles = @()
foreach ($f in $requiredFiles) {
    if (-not (Test-Path $f)) {
        $missingFiles += $f
        Write-Warning "MISSING: $f"
    } else {
        Write-Host "  OK: $f"
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Error "FATAL: $($missingFiles.Count) required artifact(s) not found on the VM. The storage account download failed."
    Write-Error "Missing files:`n$($missingFiles -join "`n")"
    Write-Error "Bootstrap cannot continue. Check VM managed identity permissions (Storage Blob Data Contributor) on the storage account and ensure artifacts were uploaded."
    Stop-Transcript
    exit 1
}

Write-Host "All $($requiredFiles.Count) required artifacts verified successfully." -ForegroundColor Green
# -------------------------------------------------------------------

New-Item -path alias:azdata -value 'C:\Program Files (x86)\Microsoft SDKs\Azdata\CLI\wbin\azdata.cmd'

# Disable Microsoft Edge sidebar
$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$Name = 'HubsSidebarEnabled'
$Value = '00000000'
# Create the key if it does not exist
If (-NOT (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}
New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType DWORD -Force

# Disable Microsoft Edge first-run Welcome screen
$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$Name = 'HideFirstRunExperience'
$Value = '00000001'
# Create the key if it does not exist
If (-NOT (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}
New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType DWORD -Force

# Set Diagnostic Data settings

$telemetryPath = "HKLM:\Software\Policies\Microsoft\Windows\DataCollection"
$telemetryProperty = "AllowTelemetry"
$telemetryValue = 3

$oobePath = "HKLM:\Software\Policies\Microsoft\Windows\OOBE"
$oobeProperty = "DisablePrivacyExperience"
$oobeValue = 1

# Create the registry key and set the value for AllowTelemetry
if (-not (Test-Path $telemetryPath)) {
    New-Item -Path $telemetryPath -Force | Out-Null
}
Set-ItemProperty -Path $telemetryPath -Name $telemetryProperty -Value $telemetryValue

# Create the registry key and set the value for DisablePrivacyExperience
if (-not (Test-Path $oobePath)) {
    New-Item -Path $oobePath -Force | Out-Null
}
Set-ItemProperty -Path $oobePath -Name $oobeProperty -Value $oobeValue

Write-Host "Registry keys and values for Diagnostic Data settings have been set successfully."

# Change RDP Port
Write-Host "RDP port number from configuration is $rdpPort"
if (($rdpPort -ne $null) -and ($rdpPort -ne "") -and ($rdpPort -ne "3389")) {
    Write-Host "Configuring RDP port number to $rdpPort"
    $TSPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $RDPTCPpath = $TSPath + '\Winstations\RDP-Tcp'
    Set-ItemProperty -Path $TSPath -name 'fDenyTSConnections' -Value 0

    # RDP port
    $portNumber = (Get-ItemProperty -Path $RDPTCPpath -Name 'PortNumber').PortNumber
    Write-Host "Current RDP PortNumber: $portNumber"
    if (!($portNumber -eq $rdpPort)) {
        Write-Host Setting RDP PortNumber to $rdpPort
        Set-ItemProperty -Path $RDPTCPpath -name 'PortNumber' -Value $rdpPort
        Restart-Service TermService -force
    }

    #Setup firewall rules
    if ($rdpPort -eq 3389) {
        netsh advfirewall firewall set rule group="remote desktop" new Enable=Yes
    }
    else {
        $systemroot = get-content env:systemroot
        netsh advfirewall firewall add rule name="Remote Desktop - Custom Port" dir=in program=$systemroot\system32\svchost.exe service=termservice action=allow protocol=TCP localport=$RDPPort enable=yes
    }

    Write-Host "RDP port configuration complete."
}

# Workaround for https://github.com/microsoft/azure_arc/issues/3035

# Define firewall rule name
$ruleName = "Block RDP UDP 3389"

# Check if the rule already exists
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($existingRule) {
    Write-Host "Firewall rule '$ruleName' already exists. No changes made."
} else {
    # Create a new firewall rule to block UDP traffic on port 3389
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol UDP -LocalPort 3389 -Action Block -Enabled True
    Write-Host "Firewall rule '$ruleName' created successfully. RDP UDP is now blocked."
}

# Define the registry path
$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"

# Define the registry key name
$registryName = "fClientDisableUDP"

# Define the value (1 = Disable Connect Time Detect and Continuous Network Detect)
$registryValue = 1

# Check if the registry path exists, if not, create it
if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}

# Set the registry key
Set-ItemProperty -Path $registryPath -Name $registryName -Value $registryValue -Type DWord

# Confirm the change
Write-Host "Registry setting applied successfully. fClientDisableUDP set to $registryValue"

Write-Header "Configuring Logon Scripts"

$ScheduledTaskExecutable = "pwsh.exe"

$DeploymentProgressString = "Restarting and installing WinGet packages..."

$tags = Get-AzResourceGroup -Name $resourceGroup | Select-Object -ExpandProperty Tags

if ($null -ne $tags) {
    $tags["DeploymentProgress"] = $DeploymentProgressString
} else {
    $tags = @{"DeploymentProgress" = $DeploymentProgressString}
}

$null = Set-AzResourceGroup -ResourceGroupName $resourceGroup -Tag $tags

if ($flavor -eq "ITPro") {
    # Creating scheduled task for WinGet.ps1
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Action = New-ScheduledTaskAction -Execute $ScheduledTaskExecutable -Argument $Env:ArcBoxDir\WinGet.ps1
    Register-ScheduledTask -TaskName "WinGetLogonScript" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force
    # Creating scheduled task for ArcServersLogonScript.ps1
    $Action = New-ScheduledTaskAction -Execute $ScheduledTaskExecutable -Argument $Env:ArcBoxDir\ArcServersLogonScript.ps1
    Register-ScheduledTask -TaskName "ArcServersLogonScript" -User $adminUsername -Action $Action -RunLevel "Highest" -Force
}

if ($flavor -eq "DevOps") {
    # Creating scheduled task for WinGet.ps1
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Action = New-ScheduledTaskAction -Execute $ScheduledTaskExecutable -Argument $Env:ArcBoxDir\WinGet.ps1
    Register-ScheduledTask -TaskName "WinGetLogonScript" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force
    # Creating scheduled task for DevOpsLogonScript.ps1
    $Action = New-ScheduledTaskAction -Execute $ScheduledTaskExecutable -Argument $Env:ArcBoxDir\DevOpsLogonScript.ps1
    Register-ScheduledTask -TaskName "DevOpsLogonScript" -User $adminUsername -Action $Action -RunLevel "Highest" -Force
}

if ($flavor -eq "DataOps") {

    # Joining ClientVM to AD DS domain
    if ($null -eq $addsDomainName){
        $addsDomainName = "jumpstart.local"
    }

    $netbiosname = $addsDomainName.Split(".")[0]
    $computername = $env:COMPUTERNAME

    $domainCred = New-Object pscredential -ArgumentList ([pscustomobject]@{
            UserName = "${netbiosname}\${adminUsername}"
            Password = (ConvertTo-SecureString -String $adminPassword -AsPlainText -Force)[0]
        })

    $localCred = New-Object pscredential -ArgumentList ([pscustomobject]@{
            UserName = "${computername}\${adminUsername}"
            Password = (ConvertTo-SecureString -String $adminPassword -AsPlainText -Force)[0]
        })

    # Register schedule task to run after system reboot
    # schedule task to run after reboot to create reverse DNS lookup
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "$Env:ArcBoxDir\RunAfterClientVMADJoin.ps1"
    Register-ScheduledTask -TaskName "RunAfterClientVMADJoin" -Trigger $Trigger -User SYSTEM -Action $Action -RunLevel "Highest" -Force
    Write-Host "Registered scheduled task 'RunAfterClientVMADJoin' to run after Client VM AD join."

    Write-Host "Joining client VM to domain"
    Add-Computer -DomainName $addsDomainName -LocalCredential $localCred -Credential $domainCred
    Write-Host "Joined Client VM to $addsDomainName domain."

    # Disabling Windows Server Manager Scheduled Task
    Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

    # Install Hyper-V and reboot
    Write-Host "Installing Hyper-V and restart"
    Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
    Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools -Restart

    # Clean up Bootstrap.log
    Stop-Transcript
    $logSuppress = Get-Content $bootstrapLogFile | Where-Object { $_ -notmatch "Host Application: $ScheduledTaskExecutable" }
    $logSuppress | Set-Content $bootstrapLogFile -Force

    # Restart computer
    Restart-Computer
}
else {

    # Creating scheduled task for MonitorWorkbookLogonScript.ps1

    $Action = New-ScheduledTaskAction -Execute $ScheduledTaskExecutable -Argument $Env:ArcBoxDir\MonitorWorkbookLogonScript.ps1
    Register-ScheduledTask -TaskName "MonitorWorkbookLogonScript" -User $adminUsername -Action $Action -RunLevel "Highest" -Force

    # Disabling Windows Server Manager Scheduled Task
    Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

    if ($flavor -eq "ITPro") {

    Write-Header "Installing Hyper-V"

    # Install Hyper-V and reboot
    # Use -NoRestart so the unconditional Restart-Computer below owns the restart.
    # Using -Restart here causes a shutdown-in-progress conflict with that call.
    Write-Host "Installing Hyper-V and restart"
    Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
    Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools

    }

    # Clean up Bootstrap.log
    Write-Host "Clean up Bootstrap.log"
    Stop-Transcript
    $logSuppress = Get-Content $Env:ArcBoxLogsDir\Bootstrap.log | Where-Object { $_ -notmatch "Host Application: $ScheduledTaskExecutable" }
    $logSuppress | Set-Content $Env:ArcBoxLogsDir\Bootstrap.log -Force
}

# Restart computer
Restart-Computer