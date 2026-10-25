# Q13 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q13 cp setup/check.sh cks-q13:/tmp/q13-check.sh | Out-Null
minikube -p cks-q13 ssh -- "sudo -i bash /tmp/q13-check.sh; sudo rm -f /tmp/q13-check.sh"
