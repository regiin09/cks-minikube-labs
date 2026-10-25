# Q02 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q02 cp setup/check.sh cks-q02:/tmp/q02-check.sh | Out-Null
minikube -p cks-q02 ssh -- "sudo bash /tmp/q02-check.sh; sudo rm -f /tmp/q02-check.sh"
