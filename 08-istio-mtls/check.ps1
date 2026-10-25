# Q08 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q08 cp setup/check.sh cks-q08:/tmp/q08-check.sh | Out-Null
minikube -p cks-q08 ssh -- "sudo -i bash /tmp/q08-check.sh; sudo rm -f /tmp/q08-check.sh"
