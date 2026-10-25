# Q10 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q10 cp setup/check.sh cks-q10:/tmp/q10-check.sh | Out-Null
minikube -p cks-q10 ssh -- "sudo -i bash /tmp/q10-check.sh; sudo rm -f /tmp/q10-check.sh"
