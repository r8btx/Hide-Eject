$DEVICE_CAPABILITIES = @{
  # As defined in cfgmgr32.h
  'REMOVABLE' = 0x00000004;
}

$HIDE_EJECT_MASK = -bnot $DEVICE_CAPABILITIES['REMOVABLE'];
$REGISTRY_ROOT = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'
$CapabilityUpdateScheduleName = "Hide-Eject"

function Restart-Explorer () {
  $OpenWindowObjects = @((New-Object -com shell.application).Windows()).Document.Folder
  $OpenWindowPaths = $OpenWindowObjects | Select-Object -Property @{ Name = "Path"; Expression = { $_.Self.Path } }
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

  Start-Sleep -Milliseconds 500
  while (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
    Start-Process explorer.exe
    Start-Sleep -Milliseconds 500
  }

  foreach ($p in $OpenWindowPaths) {
    Invoke-Item "$($p.Path)" -ErrorAction SilentlyContinue
  }
}

function Find-CapabilityUpdateSchedule () {
  $ScheduledTask = Get-ScheduledJob -Name $CapabilityUpdateScheduleName -ErrorAction SilentlyContinue
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
  $CodeString += "REG.exe ADD `"$($RegistryPath)`" /v Capabilities /t REG_DWORD /d $($UpdatedCapabilities) /f;"
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
  return Get-ItemPropertyValue -Name Capabilities -Path "REGISTRY::$($RegistryPath)" -EA Stop
}

function Hide-Eject () {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline = $true,ValueFromPipelineByPropertyName = $true,Mandatory = $true,Position = 0)]
    [Alias("InputObject")]
    [ValidateNotNullOrEmpty()]
    [Microsoft.Management.Infrastructure.CimInstance[]]
    $CimInstance,

    [switch]
    $Permanent,

    [switch]
    $Rollback
  )

  begin {
    Write-Host "Hide-Eject was called with the following options:"
  }

  process {
    if (!$PrintedOptions) { Write-Host "{ $($MyInvocation.BoundParameters.Keys) }`n" }
    $PrintedOptions = $true

    foreach ($Instance in $CimInstance) {
      $CurrentCapabilities = Get-DeviceCurrentCapabilities $Instance
      $UpdatedCapabilities = $CurrentCapabilities -band $HIDE_EJECT_MASK;
      $RegistryPath = $REGISTRY_ROOT + $Instance.InstanceId

      if ($Rollback) {
        Remove-CapabilityUpdateSchedule $RegistryPath
      } else {
        REG.exe ADD `"$($RegistryPath)`" /v Capabilities /t REG_DWORD /d $($UpdatedCapabilities) /f
        if ($Permanent) {
          Add-CapabilityUpdateSchedule $RegistryPath $UpdatedCapabilities
        }
      }
    }
  }

  end {
    if (!$Rollback) { Restart-Explorer }
    Write-Host "`nComplete.`n"
  }
}

Write-Host "Hide Eject Loaded. [v0.4]`n"
