# Q11 setup: single node with Calico (enforces NetworkPolicy), namespace prod with
# web + api + client, a client in an ALLOWED namespace and one in a NOT-allowed
# namespace (names picked at random each run). No policies yet.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q11"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

$pick = @("frontend", "monitoring", "partners", "staging", "analytics") | Sort-Object { Get-Random } | Select-Object -First 2
$A = $pick[0]; $O = $pick[1]
$yaml = (Get-Content yaml/workloads.yaml -Raw).Replace("__ALLOWED__", $A).Replace("__OTHER__", $O)
$tmp = Join-Path ([IO.Path]::GetTempPath()) "q11-workloads.yaml"
[IO.File]::WriteAllText($tmp, $yaml)

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --cni=calico --keep-context }

Write-Host ">> waiting for Calico"
Step { kubectl --context $P -n kube-system rollout status ds/calico-node --timeout=300s }
Step { kubectl --context $P -n kube-system rollout status deploy/calico-kube-controllers --timeout=300s }
# pods that started before Calico may have minikube's bridge IPs; recreate CoreDNS on Calico
kubectl --context $P -n kube-system rollout restart deploy/coredns | Out-Null
Step { kubectl --context $P -n kube-system rollout status deploy/coredns --timeout=180s }

Step { minikube -p $P ssh -- mkdir -p /tmp/q11 }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/q11/break-node.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q11/break-node.sh $A $O }
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/q11/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q11/node-tools.sh }
minikube -p $P ssh -- sudo rm -rf /tmp/q11

Step { kubectl --context $P apply -f $tmp }
Remove-Item $tmp
foreach ($ns in "prod", $A, $O) {
  Step { kubectl --context $P -n $ns wait --for=condition=available deploy --all --timeout=300s }
}

Write-Host ""
Write-Host "Allowed namespace this run: $A   (task: /opt/course/11/task.txt on the node)" -ForegroundColor Cyan
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
