# Q11 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q11 cp setup/check.sh cks-q11:/tmp/q11-check.sh | Out-Null
minikube -p cks-q11 ssh -- "sudo -i bash /tmp/q11-check.sh; sudo rm -f /tmp/q11-check.sh"
