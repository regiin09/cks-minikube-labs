# Q03 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q03 cp setup/check.sh cks-q03:/tmp/q03-check.sh | Out-Null
minikube -p cks-q03 ssh -- "sudo bash /tmp/q03-check.sh; sudo rm -f /tmp/q03-check.sh"
