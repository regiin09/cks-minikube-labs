# Q04 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q04 cp setup/check.sh cks-q04:/tmp/q04-check.sh | Out-Null
minikube -p cks-q04 ssh -- "sudo -i bash /tmp/q04-check.sh 1.35.1 cks-q04-m02; sudo rm -f /tmp/q04-check.sh"
