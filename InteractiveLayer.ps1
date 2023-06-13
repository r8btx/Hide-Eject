$TargetDevice = [pscustomobject]@{
  Instance = ''
  Action = ''
}

function Get-HideEjectCandidates {
  do {
    try {
      $DeviceName = Read-Host "What device do you want to hide?`nName of the device"
      $CimInstance = Get-PnpDevice | Where-Object FriendlyName -Match $DeviceName -ErrorAction Stop
      if ($CimInstance) {
        return $CimInstance
      }
      else {
        throw "Device not found. Verify your input and retry.`n"
      }
    }
    catch {
      Write-Host $_.Exception.Message
    }
  }
  while ($true)
}

function Select-HideEjectDeviceInstance {
  param(
    [Parameter(Mandatory = $true,Position = 0)]
    [Microsoft.Management.Infrastructure.CimInstance[]]
    $CimInstances
  )

  $Options = $CimInstances | ForEach-Object {
    [pscustomobject]@{
      Option = $CimInstances.IndexOf($_) + 1
      FriendlyName = $_.FriendlyName
      InstanceId = $_.InstanceId
    }
  }
  $Options += [pscustomobject]@{ Option = $Options.Count + 1; FriendlyName = "Cancel and Quit" }

  do {
    Write-Host "Enter the option number of the device for operation:"
    $Options | Format-Table | Out-Host

    $Response = Read-Host "Your choice"
    $Choice = if ($Response -match '^\d+$') { [int]$Response } else { 0 }
    Write-Host "`n"
  }
  while ($Choice -le 0 -or $Choice -gt $Options.Count)

  if ($Choice -eq $Options.Count) {
    exit
  }

  $TargetDevice.Instance = $CimInstances[$Choice - 1]
}

function Get-HideEjectAction {
  Write-Host "`nDevice: $($TargetDevice.Instance.FriendlyName)`n"

  $Hide = New-Object System.Management.Automation.Host.ChoiceDescription "&Hide","Hide device for the duration of the current logon session"
  $Permanent = New-Object System.Management.Automation.Host.ChoiceDescription "&Permanent","Set up a task schedule to hide the device on each logon"
  $Rollback = New-Object System.Management.Automation.Host.ChoiceDescription "&Rollback","Undo 'Permanent' option"
  $Cancel = New-Object System.Management.Automation.Host.ChoiceDescription "&Cancel","Cancel and Quit"
  $Options = [System.Management.Automation.Host.ChoiceDescription[]]($Hide,$Permanent,$Rollback,$Cancel)

  $choiceResult = $host.UI.PromptForChoice('','Which action do you want to perform?',$Options,1)

  switch ($choiceResult) {
    0 { $TargetDevice.Action = "Hide" }
    1 { $TargetDevice.Action = "Permanent" }
    2 { $TargetDevice.Action = "Rollback" }
    3 { exit }
  }
}

function Get-HideEjectConfirmation {
  $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Continue"
  $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Quit"
  $Options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)

  Write-Host "`nYou are about to perform the following operation:`n"
  Write-Host "  - Device: $($TargetDevice.Instance.FriendlyName)"
  Write-Host "  - Action: $($TargetDevice.Action)"
  Write-Host "`nWhich will involve:`n"

  switch ($TargetDevice.Action) {
    "Hide" {
      Write-Host "  - Editing Registry Values"
      Write-Host "  - Restarting Windows File Explorer"
    }
    "Permanent" {
      Write-Host "  - Editing Registry Values"
      Write-Host "  - Restarting Windows File Explorer"
      Write-Host "  - Modifying Task Schedule"
    }
    "Rollback" {
      Write-Host "  - Modifying Task Schedule"
    }
  }

  $confirmationResult = $host.UI.PromptForChoice("`n",'Continue?',$Options,0)
  return $confirmationResult
}

function Start-HideEjectInteractiveLayer {
  $Candidates = Get-HideEjectCandidates

  if ($Candidates.Count -gt 1) {
    Write-Host "`nThere is more than one device that matches your specification."
    Select-HideEjectDeviceInstance $Candidates
  }
  else {
    $TargetDevice.Instance = $Candidates
  }

  Get-HideEjectAction

  $Stop = Get-HideEjectConfirmation

  if ($Stop) {
    exit
  }

  Write-Host
  switch ($TargetDevice.Action) {
    "Hide" {
      $TargetDevice.Instance | Hide-Eject
    }
    "Permanent" {
      $TargetDevice.Instance | Hide-Eject -Permanent
    }
    "Rollback" {
      $TargetDevice.Instance | Hide-Eject -Rollback
    }
  }
}

try {
  $ScriptPath = Join-Path $PSScriptRoot "HideEject.ps1"
  .$ScriptPath

  Start-HideEjectInteractiveLayer
}
catch {
  Write-Host $_.Exception.Message
}

Pause
