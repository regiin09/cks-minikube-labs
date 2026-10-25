# Q06 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q06 cp setup/check.sh cks-q06:/tmp/q06-check.sh | Out-Null
minikube -p cks-q06 ssh -- "sudo -i bash /tmp/q06-check.sh; sudo rm -f /tmp/q06-check.sh"
