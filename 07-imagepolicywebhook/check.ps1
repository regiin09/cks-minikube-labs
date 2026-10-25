# Q07 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q07 cp setup/check.sh cks-q07:/tmp/q07-check.sh | Out-Null
minikube -p cks-q07 ssh -- "sudo -i bash /tmp/q07-check.sh; sudo rm -f /tmp/q07-check.sh"
