$DEVICE_CAPABILITIES = @{
  # As defined in cfgmgr32.h
  'EJECTSUPPORTED' = 0x00000002;
  'REMOVABLE'      = 0x00000004;
}

$HIDE_EJECT_MASK = -bnot ($DEVICE_CAPABILITIES['EJECTSUPPORTED'] -bor $DEVICE_CAPABILITIES['REMOVABLE']);
$REGISTRY_INSTANCEROOT = 'REGISTRY::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'
$CapabilityUpdateScheduleName = "Hide-Eject"

function Update-SystemTray () {
  Start-Sleep -Milliseconds 300  # Useful during the scheduled operation. Fix this later?
  $SysTrayRegPath = 'REGISTRY::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Applets\SysTray'
  $OriginalValue = Get-ItemPropertyValue -Name Services -Path $SysTrayRegPath -ErrorAction SilentlyContinue
  Set-ItemProperty -Name Services -Path $SysTrayRegPath -Value 29
  If (&systray.exe) {
    Set-ItemProperty -Name Services -Path $SysTrayRegPath -Value $OriginalValue -ErrorAction SilentlyContinue
  }
}

function Find-CapabilityUpdateSchedule () {
  $ScheduledTask = Get-ScheduledJob -Name $CapabilityUpdateScheduleName -ErrorAction SilentlyContinue
  return $ScheduledTask
}

function Add-CapabilityUpdateSchedule () {
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]
    $RegistryPath,

    [Parameter(Mandatory = $true, Position = 1)]
    [int]
    $UpdatedCapabilities
  )

  $Trigger = New-JobTrigger -AtStartup
  $Options = New-ScheduledJobOption -RunElevated -StartIfOnBattery
  $ScheduledTask = Find-CapabilityUpdateSchedule

  $RegisteredCode = $null
  $CodeArray = $null
  $CodeString = ""
  $SysTrayCodeBlock = (Get-Command -Name Update-SystemTray).ScriptBlock.ToString() -Replace "`r`n\s*", ";"

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
    $Idx = $CodeString.IndexOf(';;')
    $CodeString = $CodeString.Substring(0, $Idx) + ';'
  }
  $CodeString += "Set-ItemProperty -Name Capabilities -Path `"$($RegistryPath)`" -Value $($UpdatedCapabilities) -EA 0;"
  $CodeString += $SysTrayCodeBlock
  $Code = [scriptblock]::Create($CodeString)

  $null = Register-ScheduledJob -Name $CapabilityUpdateScheduleName -Trigger $Trigger -ScheduledJobOption $Options -ScriptBlock $Code
}

function Remove-CapabilityUpdateSchedule () {
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]
    $RegistryPath
  )

  $Message = "The device is not scheduled to be hidden."
  $ScheduledTask = Find-CapabilityUpdateSchedule

  $CodeArray = $null

  if ($ScheduledTask) {
    $CodeArray = $ScheduledTask.Command.Split(';')
  }
  else {
    Write-Host $Message
    return
  }

  $RemovedCode = $CodeArray | Where-Object { !$_.Contains($RegistryPath) }
  if ($CodeArray.Count -eq $RemovedCode.Count) {
    Write-Host $Message
  }
  else {
    $CodeString = $RemovedCode -join ';'
    $Code = [scriptblock]::Create($CodeString)
    $Trigger = New-JobTrigger -AtStartup
    $Options = New-ScheduledJobOption -RunElevated -StartIfOnBattery

    Unregister-ScheduledJob $ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    if (($CodeArray | Where-Object { $_.Contains($REGISTRY_INSTANCEROOT) }).Count -gt 1) {
      $null = Register-ScheduledJob -Name $CapabilityUpdateScheduleName -Trigger $Trigger -ScheduledJobOption $Options -ScriptBlock $Code
    }
  }
}

function Get-DeviceCurrentCapabilities () {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Microsoft.Management.Infrastructure.CimInstance[]]
    $CimInstance
  )

  $RegistryPath = $REGISTRY_INSTANCEROOT + $CimInstance.InstanceId
  return Get-ItemPropertyValue -Name Capabilities -Path $RegistryPath -EA Stop
}

function Hide-Eject () {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Mandatory = $true, Position = 0)]
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
      $RegistryPath = $REGISTRY_INSTANCEROOT + $Instance.InstanceId

      if ($Rollback) {
        Remove-CapabilityUpdateSchedule $RegistryPath
      }
      else {
        Set-ItemProperty -Name Capabilities -Path $RegistryPath -Value $UpdatedCapabilities -EA Stop
        if ($Permanent) {
          Add-CapabilityUpdateSchedule $RegistryPath $UpdatedCapabilities
        }
      }
    }
  }

  end {
    if (!$Rollback) { Update-SystemTray }
    Write-Host "`nComplete.`n"
  }
}

Write-Host "Hide Eject Loaded. [v0.5]`n"
