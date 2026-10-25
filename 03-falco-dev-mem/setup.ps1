# Q03 setup: single-node minikube + Falco on the node + 3 look-alike Deployments,
# one of them (random each run) reads /dev/mem.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}
function B64($s) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)) }

$names = @("nvidia", "cpu", "ollama")
$bad   = Get-Random -InputObject $names
$jobs  = @{
  bad   = 'while true; do dd if=/dev/mem of=/dev/null bs=1 count=1 2>/dev/null; sleep 10; done'
  good1 = 'while true; do dd if=/dev/zero of=/dev/null bs=1k count=64 2>/dev/null; sleep 10; done'
  good2 = 'while true; do dd if=/dev/urandom of=/dev/null bs=16 count=1 2>/dev/null; sleep 10; done'
}
$good = @($jobs.good1, $jobs.good2)
$yaml = Get-Content yaml/workloads.yaml -Raw
$i = 0
foreach ($n in $names) {
  if ($n -eq $bad) { $job = $jobs.bad } else { $job = $good[$i]; $i++ }
  $yaml = $yaml.Replace("__JOB_$($n.ToUpper())__", (B64 $job))
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) "q03-workloads.yaml"
Set-Content -Path $tmp -Value $yaml -Encoding ascii

Step { minikube start -p cks-q03 --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p cks-q03 cp setup/break-node.sh cks-q03:/tmp/break-node.sh }
Step { minikube -p cks-q03 ssh -- sudo bash /tmp/break-node.sh $bad }
Step { minikube -p cks-q03 cp ../_common/node-tools.sh cks-q03:/tmp/node-tools.sh }
Step { minikube -p cks-q03 ssh -- sudo bash /tmp/node-tools.sh }
minikube -p cks-q03 ssh -- sudo rm -f /tmp/break-node.sh /tmp/node-tools.sh
Step { kubectl --context cks-q03 apply -f $tmp }
Remove-Item $tmp
Step { kubectl --context cks-q03 -n ai wait --for=condition=available deploy --all --timeout=180s }

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p cks-q03 ssh --native-ssh=false" -ForegroundColor Green
