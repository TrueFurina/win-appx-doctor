$log = Join-Path $PSScriptRoot 'photos_repair.log'
"Photos repair started $(Get-Date)" | Out-File $log
$pkgs = @(Get-AppxPackage -AllUsers -Name 'Microsoft.Windows.Photos' -ErrorAction SilentlyContinue)
"AllUsers Microsoft.Windows.Photos packages found: $($pkgs.Count)" | Out-File $log -Append
if ($pkgs.Count -eq 0) {
  "None in AllUsers; checking current user..." | Out-File $log -Append
  $pkgs = @(Get-AppxPackage -Name 'Microsoft.Windows.Photos' -ErrorAction SilentlyContinue)
  "Current-user packages found: $($pkgs.Count)" | Out-File $log -Append
}
if ($pkgs.Count -eq 0) {
  "ERROR: Microsoft.Windows.Photos package not present on this system." | Out-File $log -Append
} else {
  foreach ($p in $pkgs) {
    "Re-registering: $($p.InstallLocation)" | Out-File $log -Append
    try {
      Add-AppxPackage -DisableDevelopmentMode -Register "$($p.InstallLocation)\AppxManifest.xml" -Verbose 2>&1 | Out-File $log -Append
      "  -> re-register OK" | Out-File $log -Append
    } catch {
      "  -> re-register FAILED: $_" | Out-File $log -Append
    }
  }
  # gentle reset as well (clears corrupted per-user app state)
  try {
    Get-AppxPackage -AllUsers -Name 'Microsoft.Windows.Photos' | Reset-AppxPackage -ErrorAction Stop
    "Reset-AppxPackage OK" | Out-File $log -Append
  } catch {
    "Reset-AppxPackage note: $_" | Out-File $log -Append
  }
}
"DONE" | Out-File $log -Append
