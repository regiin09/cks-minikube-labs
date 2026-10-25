#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same steps as the README answers.

# 1. exec into each container and check libcrypto3
for c in $(kubectl -n alpine get deploy alpine -o jsonpath='{.spec.template.spec.containers[*].name}'); do
  echo "$c: $(kubectl -n alpine exec deploy/alpine -c "$c" -- apk info -v 2>/dev/null | grep '^libcrypto3-')"
done
BAD=$(for c in $(kubectl -n alpine get deploy alpine -o jsonpath='{.spec.template.spec.containers[*].name}'); do
  kubectl -n alpine exec deploy/alpine -c "$c" -- apk info -v 2>/dev/null | grep -q '^libcrypto3-3.1.4-r5' && echo "$c"
done)
IMG=$(kubectl -n alpine get deploy alpine -o jsonpath="{.spec.template.spec.containers[?(@.name=='$BAD')].image}")
echo "$BAD" > /opt/course/05/container.txt
echo "bad container: $BAD  image: $IMG"

# 2. SBOM of that image, tag-value
bom generate --image "$IMG" --format tag-value --output /opt/course/05/sbom.spdx

# 3. remove the container from the manifest and apply
python3 - "$BAD" <<'EOF' 2>/dev/null || echo "edit /opt/course/05/alpine-deployment.yaml by hand"
import sys, re
bad = sys.argv[1]
p = "/opt/course/05/alpine-deployment.yaml"
s = open(p).read()
s = re.sub(r"      - name: %s\n(        .*\n)+" % re.escape(bad), "", s)
open(p, "w").write(s)
EOF
kubectl apply -f /opt/course/05/alpine-deployment.yaml
kubectl -n alpine rollout status deploy/alpine
