param([ValidateSet('Start','Stop','Status','Check')][string]$Action='Status')
$ErrorActionPreference='Stop'
if ($Action -eq 'Stop') {
  & (Join-Path $PSScriptRoot 'manage-web-vm.ps1') -Action Stop
  & (Join-Path $PSScriptRoot 'manage-database-vms.ps1') -Action Stop
} else {
  & (Join-Path $PSScriptRoot 'manage-database-vms.ps1') -Action $Action
  & (Join-Path $PSScriptRoot 'manage-web-vm.ps1') -Action $Action
}
