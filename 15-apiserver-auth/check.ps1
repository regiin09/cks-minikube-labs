# Q15 grader: run AFTER you finish (from this folder):  .\check.ps1
Set-Location $PSScriptRoot
minikube -p cks-q15 cp setup/check.sh cks-q15:/tmp/q15-check.sh | Out-Null
minikube -p cks-q15 ssh -- "sudo -i bash /tmp/q15-check.sh; sudo rm -f /tmp/q15-check.sh"
