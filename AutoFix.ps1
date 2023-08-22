function Write-Red {
  param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]
    $text,

    [switch]
    $NoNewline
  )

  Write-Host $text -ForegroundColor Red -NoNewline:$NoNewline
}

function Start-AutoFix {
  Write-Red "---------------------------------------------------------------------------------------------"
  Write-Red "This script modifies registry values and adds a scheduled task."
  Write-Red "By using this script, you are fully responsible for any harm or damage caused by this script."
  Write-Red "---------------------------------------------------------------------------------------------"
  Write-Host

  Write-Host "Disconnect all devices and leave only the devices that need to be processed."
  Write-Host "When you are ready, press " -NoNewline
  Write-Host "ENTER" -BackgroundColor Black -ForegroundColor Green -NoNewline
  Write-Host "."
  Read-Host
  
  $Candidates = Find-SafelyRemoveHardwareDevices
  if ($Candidates.Count -eq 0) {
    Write-Host "Device not found. Try other methods."
    Read-Host
    exit
  }
  else {
    Write-Host "The following device(s) will be processed."
    foreach ($c in $Candidates) {
      Write-Host "- $($c.Name)"
    }
    Write-Host "`nTo continue, press " -NoNewline
    Write-Host "ENTER" -BackgroundColor Black -ForegroundColor Green -NoNewline
    Write-Host "."
    Read-Host
  }

  $Candidates | Get-PnpDevice | Hide-Eject -Permanent
}

try {
  $ScriptPath1 = Join-Path $PSScriptRoot "SetupAPITools.ps1"
  $ScriptPath2 = Join-Path $PSScriptRoot "HideEject.ps1"
  .$ScriptPath1
  .$ScriptPath2

  Start-AutoFix
}
catch {
  Write-Host $_.Exception.Message
}

Pause
