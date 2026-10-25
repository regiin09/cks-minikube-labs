#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same steps as the README answers.
# 1. see what PSA rejects
kubectl -n team-red get events --field-selector reason=FailedCreate -o jsonpath='{.items[-1:].message}'; echo

# 2. write the fixed manifest and apply it
cat > /opt/course/14/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-server
  namespace: team-red
  labels:
    app: web-server
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-server
  template:
    metadata:
      labels:
        app: web-server
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged:1.27-alpine
        ports:
        - containerPort: 8080
        securityContext:
          readOnlyRootFilesystem: false
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
EOF
kubectl apply -f /opt/course/14/deployment.yaml
kubectl -n team-red rollout status deploy/web-server --timeout=120s
kubectl -n team-red get pods -o wide
