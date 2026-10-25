# Q04 setup: 2-node minikube. Control plane v1.35.1, worker downgraded to apt-managed
# kubeadm/kubelet/kubectl 1.35.0 (held). Root on the control plane can "ssh node01".
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q04"; $W = "cks-q04-m02"; $NEW = "1.35.1"; $OLD = "1.35.0"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=2 --cpus=2 --memory=2048 --kubernetes-version=v$NEW --keep-context }

# control plane: exam shell (kubectl, k, completion, vim) + ssh key/config for node01
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/node-tools.sh }
$ip = (minikube -p $P ip -n $W).Trim()
Step { minikube -p $P cp setup/master.sh "${P}:/tmp/master.sh" }
$pub = (minikube -p $P ssh -- sudo bash /tmp/master.sh $ip $W | Select-Object -Last 1).Trim()
if (-not $pub) { Write-Host "FAILED: no ssh key from master" -ForegroundColor Red; exit 1 }

# worker: apt-managed kubeadm/kubelet/kubectl at the OLD version, held
Step { minikube -p $P cp setup/worker.sh "${W}:/tmp/worker.sh" }
Step { minikube -p $P ssh -n $W -- sudo bash /tmp/worker.sh $OLD $pub }
minikube -p $P ssh -- sudo rm -f /tmp/node-tools.sh /tmp/master.sh
minikube -p $P ssh -n $W -- sudo rm -f /tmp/worker.sh

# workloads that make the drain flags matter
(Get-Content yaml/workloads.yaml -Raw).Replace("__WORKER__", $W) | kubectl --context $P apply -f -
Step { kubectl --context $P wait --for=condition=available deploy --all --timeout=180s }
kubectl --context $P get nodes

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
