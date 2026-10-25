# Q14 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q14 cp setup/check.sh cks-q14:/tmp/q14-check.sh | Out-Null
minikube -p cks-q14 ssh -- "sudo -i bash /tmp/q14-check.sh; sudo rm -f /tmp/q14-check.sh"
