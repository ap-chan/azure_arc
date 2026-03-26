$ErrorActionPreference = $env:ErrorActionPreference

$Env:ArcBoxDir = 'C:\ArcBox'
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$tenantId = $env:tenantId
$subscriptionId = $env:subscriptionId
$resourceGroup = $env:resourceGroup

$logFilePath = Join-Path -Path $Env:ArcBoxLogsDir -ChildPath ('WinGet-provisioning-' + (Get-Date -Format 'yyyyMMddHHmmss') + '.log')

Start-Transcript -Path $logFilePath -Force -ErrorAction SilentlyContinue

$DeploymentProgressString = "Installing WinGet packages..."

if ($env:azureEnvironment -eq 'AzureUSGovernment') {
    Connect-AzAccount -Identity -Tenant $tenantId -Subscription $subscriptionId -Environment AzureUSGovernment
} else {
    Connect-AzAccount -Identity -Tenant $tenantId -Subscription $subscriptionId
}

$tags = Get-AzResourceGroup -Name $resourceGroup | Select-Object -ExpandProperty Tags

if ($null -ne $tags) {
    $tags["DeploymentProgress"] = $DeploymentProgressString
} else {
    $tags = @{"DeploymentProgress" = $DeploymentProgressString}
}

$null = Set-AzResourceGroup -ResourceGroupName $resourceGroup -Tag $tags
$null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $resourceGroup -ResourceType "microsoft.compute/virtualmachines" -Tag $tags -Force

# Install WinGet PowerShell module (client only, DSC module is deprecated)
Install-PSResource -Name Microsoft.WinGet.Client -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Version 1.11.460

# Update WinGet package manager to the latest version (running twice due to a known issue regarding WinAppSDK)
Repair-WinGetPackageManager -AllUsers -Force -Latest -Verbose
Repair-WinGetPackageManager -AllUsers -Force -Latest -Verbose

# Common WinGet packages (replaces common.dsc.yml)
$commonPackages = @(
    'Git.Git',
    'Microsoft.VisualStudioCode',
    'Microsoft.AzureCLI',
    'Microsoft.PowerShell',
    'Kubernetes.kubectl',
    'Microsoft.Edge',
    'Microsoft.Azure.AZCopy.10',
    'Microsoft.DotNet.SDK.8',
    'Helm.Helm',
    'Microsoft.Sysinternals.BGInfo',
    'FireDaemon.OpenSSL'
)

# Install DHCP Windows Features (replaces common.dsc.yml WindowsFeature resources)
Install-WindowsFeature -Name DHCP -IncludeManagementTools

# Flavor-specific packages and configuration (replaces flavor .dsc.yml files)
$flavorPackages = @()
switch ($env:flavor) {
    'ITPro' {
        $flavorPackages = @('7zip.7zip')
        # Hyper-V already installed by Bootstrap.ps1
        # Configure VM Host (replaces HyperVDsc/VMHost from itpro.dsc.yml)
        Set-VMHost -EnableEnhancedSessionMode $true
        # Create VM Switch (replaces HyperVDsc/VMSwitch from itpro.dsc.yml)
        if (-not (Get-VMSwitch -Name 'InternalNATSwitch' -ErrorAction SilentlyContinue)) {
            New-VMSwitch -Name 'InternalNATSwitch' -SwitchType Internal
        }
        # Configure IP Address on VM Switch (replaces NetworkingDsc/IPAddress from itpro.dsc.yml)
        $switchAlias = 'vEthernet (InternalNATSwitch)'
        if (-not (Get-NetIPAddress -InterfaceAlias $switchAlias -IPAddress '10.10.1.1' -ErrorAction SilentlyContinue)) {
            New-NetIPAddress -InterfaceAlias $switchAlias -IPAddress '10.10.1.1' -PrefixLength 24
        }
    }
    'DevOps' {
        # TODO: Add DevOps flavor packages from devops.dsc.yml when needed
    }
    'DataOps' {
        # TODO: Add DataOps flavor packages from dataops.dsc.yml when needed
    }
}

# Install all WinGet packages using direct winget install (replaces winget configure DSC)
$allPackages = $commonPackages + $flavorPackages
foreach ($pkg in $allPackages) {
    Write-Host "Installing WinGet package: $pkg"
    winget install --id $pkg --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install $pkg (exit code: $LASTEXITCODE). Retrying..."
        Start-Sleep -Seconds 5
        winget install --id $pkg --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1
    }
}

# Refresh PATH so newly installed tools (az, azcopy, etc.) are available to logon scripts
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

# Start remaining logon scripts
Get-ScheduledTask *LogonScript* | Start-ScheduledTask

#Cleanup
Unregister-ScheduledTask -TaskName 'WinGetLogonScript' -Confirm:$false
Stop-Transcript