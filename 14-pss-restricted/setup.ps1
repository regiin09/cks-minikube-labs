# Q14 setup: single node, namespace team-red enforcing the "restricted" Pod Security Standard,
# Deployment web-server whose Pods are rejected (4 base violations + 2 random extras).
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q14"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

# keep 2 of the 5 extra violations, at random
$keep = @("hostnet", "privileged", "root", "netadmin", "hostpath") | Sort-Object { Get-Random } | Select-Object -First 2
$lines = Get-Content yaml/deployment.yaml | Where-Object { $_ -notmatch '^# ' } | ForEach-Object {
  if ($_ -match '#x:(\w+)\s*$') { if ($keep -contains $Matches[1]) { $_ -replace '\s*#x:\w+\s*$', '' } }
  else { $_ }
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) "deployment.yaml"
[IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"))

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p $P ssh -- mkdir -p /tmp/q14 }
Step { Push-Location ([IO.Path]::GetTempPath()); minikube -p $P cp deployment.yaml "${P}:/tmp/q14/deployment.yaml"; Pop-Location }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/q14/break-node.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q14/break-node.sh }
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/q14/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q14/node-tools.sh }
minikube -p $P ssh -- sudo rm -rf /tmp/q14
Step { kubectl --context $P apply -f yaml/namespace.yaml }
Step { kubectl --context $P apply -f $tmp 2>$null }   # hide the PodSecurity warning: finding it is the task
Remove-Item $tmp

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
