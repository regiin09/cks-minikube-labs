# Q05 setup: single node, bom installed, Deployment "alpine" with 3 containers on 3 alpine
# tags (shuffled each run). Exactly one tag ships libcrypto3 3.1.4-r5 (alpine:3.19.1).
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q05"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

# 3.19.1 -> libcrypto3 3.1.4-r5 (target), 3.20.0 -> 3.3.0-r2, 3.21.3 -> 3.3.3-r0
$tags = @("3.19.1", "3.20.0", "3.21.3") | Sort-Object { Get-Random }
$names = @("alpine-a", "alpine-b", "alpine-c")
$bad = $names[[array]::IndexOf($tags, "3.19.1")]
$yaml = (Get-Content yaml/alpine-deployment.yaml -Raw).
  Replace("__IMG_A__", $tags[0]).Replace("__IMG_B__", $tags[1]).Replace("__IMG_C__", $tags[2])
$tmp = Join-Path ([IO.Path]::GetTempPath()) "alpine-deployment.yaml"
[IO.File]::WriteAllText($tmp, $yaml)

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p $P ssh -- mkdir -p /tmp/q05 }
Step { Push-Location ([IO.Path]::GetTempPath()); minikube -p $P cp alpine-deployment.yaml "${P}:/tmp/q05/alpine-deployment.yaml"; Pop-Location }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/q05/break-node.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q05/break-node.sh $bad }
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/q05/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q05/node-tools.sh }
minikube -p $P ssh -- sudo rm -rf /tmp/q05
Step { kubectl --context $P apply -f $tmp }
Remove-Item $tmp
Step { kubectl --context $P -n alpine rollout status deploy/alpine --timeout=180s }

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
