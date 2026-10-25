# SOLUTION: upgrade worker cks-q04-m02 (node01) from 1.35.0 to 1.35.1

Tested end to end on this lab: grader 11/11.

```bash
# --- on the control plane (minikube -p cks-q04 ssh --native-ssh=false ; sudo -i) ---
k get nodes                                   # control plane v1.35.1, worker v1.35.0
k drain cks-q04-m02 --ignore-daemonsets --delete-emptydir-data --force

ssh node01                                    # (= ssh cks-q04-m02)
sudo -i

# --- on the worker ---
apt update
apt-cache madison kubeadm | grep 1.35.1       # -> 1.35.1-1.1  (NOT the top line 1.35.9!)
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.35.1-1.1
apt-mark hold kubeadm
kubeadm version -o short                      # v1.35.1

kubeadm upgrade node                          # "...successfully upgraded!"

apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.35.1-1.1 kubectl=1.35.1-1.1
apt-mark hold kubelet kubectl

systemctl daemon-reload
systemctl restart kubelet
systemctl status kubelet --no-pager | head -3
exit        # leaves sudo -i
exit        # leaves node01, back on the control plane

# --- on the control plane ---
k uncordon cks-q04-m02
k get nodes                                   # both v1.35.1, both Ready
```
