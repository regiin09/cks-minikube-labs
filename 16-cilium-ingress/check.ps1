# Q16 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q16 cp setup/check.sh cks-q16:/tmp/q16-check.sh | Out-Null
minikube -p cks-q16 ssh -- "sudo -i bash /tmp/q16-check.sh; sudo rm -f /tmp/q16-check.sh"
