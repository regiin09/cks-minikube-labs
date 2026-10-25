# Q09 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q09 cp setup/check.sh cks-q09:/tmp/q09-check.sh | Out-Null
minikube -p cks-q09 ssh -- "sudo -i bash /tmp/q09-check.sh; sudo rm -f /tmp/q09-check.sh"
