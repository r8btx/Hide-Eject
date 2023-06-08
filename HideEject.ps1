$DEVICE_CAPABILITIES = @{
  # As defined in cfgmgr32.h
  'EJECTSUPPORTED' = 0x00000002;
  'REMOVABLE' = 0x00000004;
}

$HIDE_EJECT_MASK = -bnot ($DEVICE_CAPABILITIES['EJECTSUPPORTED'] -bor $DEVICE_CAPABILITIES['REMOVABLE']);
$REGISTRY_ROOT = 'REGISTRY::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'
$CapabilityUpdateScheduleName = "Hide-Device"

function Find-CapabilityUpdateSchedule () {
  $ScheduledTask = Get-ScheduledJob -Name $CapabilityUpdateScheduleName -ErrorAction 0
  return $ScheduledTask
}

function Add-CapabilityUpdateSchedule () {
  param(
    [Parameter(Mandatory = $true,Position = 0)]
    [string]
    $RegistryPath,

    [Parameter(Mandatory = $true,Position = 1)]
    [int]
    $UpdatedCapabilities
  )

  $Trigger = New-JobTrigger -AtStartup
  $Options = New-ScheduledJobOption -RunElevated -StartIfOnBattery
  $ScheduledTask = Find-CapabilityUpdateSchedule

  $RegisteredCode = $null
  $CodeArray = $null
  $CodeString = ""

  if ($ScheduledTask) {
    $CodeArray = $ScheduledTask.Command.Split(';')
    $RegisteredCode = $CodeArray | Where-Object { $_.Contains($RegistryPath) }
    if ($RegisteredCode) {
      Write-Host "The device is already scheduled to be hidden."
      return
    }
    Unregister-ScheduledJob $ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
  }

  if ($CodeArray) {
    $CodeString = $CodeArray -join ';'
  }

  $CodeString += "Set-ItemProperty -Name Capabilities -Path `"$($RegistryPath)`" -Value $($UpdatedCapabilities) -EA 0;"
  $Code = [scriptblock]::Create($CodeString)

  $null = Register-ScheduledJob -Name $CapabilityUpdateScheduleName -Trigger $Trigger -ScheduledJobOption $Options -ScriptBlock $Code
}

function Remove-CapabilityUpdateSchedule () {
  param(
    [Parameter(Mandatory = $true,Position = 0)]
    [string]
    $RegistryPath
  )

  $Message = "The device is not scheduled to be hidden."
  $ScheduledTask = Find-CapabilityUpdateSchedule

  $CodeArray = $null

  if ($ScheduledTask) {
    $CodeArray = $ScheduledTask.Command.Split(';')
  } else {
    Write-Host $Message
    return
  }

  $RemovedCode = $CodeArray | Where-Object { !$_.Contains($RegistryPath) }
  if ($CodeArray.Count -eq $RemovedCode.Count) {
    Write-Host $Message
  } else {
    $CodeString = $RemovedCode -join ';'
    $Code = [scriptblock]::Create($CodeString)

    Unregister-ScheduledJob $ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    if ($RemovedCode.Count -gt 1) {
      $null = Register-ScheduledJob -Name $CapabilityUpdateScheduleName -Trigger $Trigger -ScheduledJobOption $Options -ScriptBlock $Code
    }
  }
}

function Get-DeviceCurrentCapabilities () {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true,Position = 0)]
    [Microsoft.Management.Infrastructure.CimInstance[]]
    $CimInstance
  )

  $RegistryPath = $REGISTRY_ROOT + $CimInstance.InstanceId
  return Get-ItemPropertyValue -Name Capabilities -Path $RegistryPath -EA Stop
}

function Hide-Eject () {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline = $true,ValueFromPipelineByPropertyName = $true,Mandatory = $true,Position = 0)]
    [Alias("InputObject")]
    [Microsoft.Management.Infrastructure.CimInstance[]]
    $CimInstance,

    [switch]
    $Permanent,

    [switch]
    $Rollback
  )

  Write-Host "Hide-Eject was called with the following options:"
  Write-Host "{ $($MyInvocation.BoundParameters.Keys) }`n"

  $CurrentCapabilities = Get-DeviceCurrentCapabilities $CimInstance
  $UpdatedCapabilities = $CurrentCapabilities -band $HIDE_EJECT_MASK;
  $RegistryPath = $REGISTRY_ROOT + $CimInstance.InstanceId

  if ($Rollback) {
    Remove-CapabilityUpdateSchedule $RegistryPath
    Write-Host "Complete.`n"
    return
  }

  Set-ItemProperty -Name Capabilities -Path $RegistryPath -Value $UpdatedCapabilities -EA Stop
  Stop-Process -Name explorer -Force

  if ($Permanent) {
    Add-CapabilityUpdateSchedule $RegistryPath $UpdatedCapabilities
  }
  Write-Host "`nComplete.`n"
}

Write-Host "Hide Eject Loaded. [v0.1]`n"