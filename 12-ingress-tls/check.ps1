# Q12 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q12 cp setup/check.sh cks-q12:/tmp/q12-check.sh | Out-Null
minikube -p cks-q12 ssh -- "sudo -i bash /tmp/q12-check.sh; sudo rm -f /tmp/q12-check.sh"
