# Q01 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q01 cp setup/check.sh cks-q01:/tmp/q01-check.sh | Out-Null
minikube -p cks-q01 ssh -- "sudo -i bash /tmp/q01-check.sh; sudo rm -f /tmp/q01-check.sh"
