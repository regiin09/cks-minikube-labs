# Q01 cleanup: deletes the cks-q01 node and frees its CPU/RAM/disk.
# Run from anywhere in PowerShell:  .\cleanup.ps1
minikube delete -p cks-q01
minikube profile list
