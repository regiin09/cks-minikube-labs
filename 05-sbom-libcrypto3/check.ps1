# Q05 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q05 cp setup/check.sh cks-q05:/tmp/q05-check.sh | Out-Null
minikube -p cks-q05 ssh -- "sudo -i bash /tmp/q05-check.sh; sudo rm -f /tmp/q05-check.sh"
