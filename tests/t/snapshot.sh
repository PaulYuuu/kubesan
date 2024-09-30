# SPDX-License-Identifier: Apache-2.0

ksan-create-volume test-pvc-1 64Mi
ksan-fill-volume test-pvc-1 64
ksan-create-snapshot test-pvc-1 test-vs-1

ksan-stage 'Deleting snapshot of volume 1...'

kubectl delete vs test-vs-1 --timeout=60s

ksan-create-snapshot test-pvc-1 test-vs-1

ksan-stage 'Creating volume 2 from snapshot of volume 1...'

kubectl create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-2
spec:
  storageClassName: kubesan
  volumeMode: Block
  dataSource:
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: test-vs-1
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 64Mi
EOF

ksan-wait-for-pvc-to-be-bound 300 test-pvc-2

ksan-stage 'Validating volume data and independence between volumes 1 and 2...'

kubectl create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  restartPolicy: Never
  containers:
    - name: container
      image: $TEST_IMAGE
      command:
        - bash
        - -c
        - |
          set -o errexit -o pipefail -o nounset -o xtrace
          cmp /var/pvc-1 /var/pvc-2
          dd if=/dev/urandom of=/var/pvc-2 conv=fsync bs=1M count=1
          ! cmp /var/pvc-1 /var/pvc-2
      volumeDevices:
        - { name: test-pvc-1, devicePath: /var/pvc-1 }
        - { name: test-pvc-2, devicePath: /var/pvc-2 }
  volumes:
    - { name: test-pvc-1, persistentVolumeClaim: { claimName: test-pvc-1 } }
    - { name: test-pvc-2, persistentVolumeClaim: { claimName: test-pvc-2 } }
EOF

ksan-wait-for-pod-to-succeed 60 test-pod
kubectl delete pod test-pod --timeout=60s

ksan-stage 'Deleting volume 1...'
kubectl delete pvc test-pvc-1 --timeout=60s

ksan-stage 'Creating volume 3 from the snapshot of volume 1 but with a bigger size...'

kubectl create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-3
spec:
  storageClassName: kubesan
  volumeMode: Block
  dataSource:
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: test-vs-1
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 128Mi
EOF

ksan-wait-for-pvc-to-be-bound 300 test-pvc-3

ksan-stage 'Validating volume data and independence between volumes 2 and 3...'

mib64="$(( 64 * 1024 * 1024 ))"

kubectl create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  restartPolicy: Never
  containers:
    - name: container
      image: $TEST_IMAGE
      command:
        - bash
        - -c
        - |
          set -o errexit -o pipefail -o nounset -o xtrace
          ! cmp -n "${mib64}" /var/pvc-2 /var/pvc-3
          cmp -n "${mib64}" /var/pvc-3 /dev/zero "${mib64}"
          dd if=/var/pvc-2 of=/var/pvc-3 conv=fsync bs=1M count=1
          cmp -n "${mib64}" /var/pvc-2 /var/pvc-3
          dd if=/dev/urandom of=/var/pvc-3 conv=fsync bs=1M count=1
          ! cmp -n "${mib64}" /var/pvc-2 /var/pvc-3
      volumeDevices:
        - { name: test-pvc-2, devicePath: /var/pvc-2 }
        - { name: test-pvc-3, devicePath: /var/pvc-3 }
  volumes:
    - { name: test-pvc-2, persistentVolumeClaim: { claimName: test-pvc-2 } }
    - { name: test-pvc-3, persistentVolumeClaim: { claimName: test-pvc-3 } }
EOF

ksan-wait-for-pod-to-succeed 60 test-pod
kubectl delete pod test-pod --timeout=60s

ksan-stage 'Deleting snapshot of volume 1...'

kubectl delete vs test-vs-1 --timeout=60s

ksan-stage 'Deleting volumes 2 and 3...'

kubectl delete pvc test-pvc-2 test-pvc-3 --timeout=60s
