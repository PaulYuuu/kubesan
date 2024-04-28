# SPDX-License-Identifier: Apache-2.0

# SOME DEFINITIONS

# Usage: start_pod <one_based_node_index>
start_pod() {
    local pod_name=test-pod-$1
    local node_name=${NODES[$1]}

    kubectl create -f - <<EOF
    apiVersion: v1
    kind: Pod
    metadata:
      name: $pod_name
    spec:
      nodeName: $node_name
      restartPolicy: Never
      containers:
        - name: container
          image: $TEST_IMAGE
          command:
            - fio
            - --name=global
            - --rw=randwrite
            - --fsync=1
            - --direct=1
            - --runtime=60m
            - --time_based=1
            - --filename=/var/pvc
            - --allow_file_create=0
            - --name=job1
          volumeDevices:
            - name: pvc
              devicePath: /var/pvc
      volumes:
        - name: pvc
          persistentVolumeClaim:
            claimName: test-pvc
EOF

    __wait_for_pod_to_start_running 60 "$pod_name"
}

# Usage: ensure_pod_is_writing <one_based_node_index>
ensure_pod_is_writing() {
    local pod_name=test-pod-$1

    sleep 10
    __pod_is_running "$pod_name"
}

# ACTUAL TEST

__create_volume test-pvc 64Mi

__stage 'Launching pod mounting the volume and writing to it...'
start_pod 0
ensure_pod_is_writing 0

__stage 'Launching another pod on a different node mounting the volume and writing to it...'
start_pod 1
ensure_pod_is_writing 1

__stage 'Ensuring that the first pod is still writing to the volume...'
ensure_pod_is_writing 0

__stage 'Deleting the first pod...'
kubectl delete pod test-pod-0 --timeout=30s

__stage 'Waiting until the blob pool has migrated...'
__poll 1 300 "__ssh_into_node 1 ! find /dev/mapper -type b -name 'subprovisioner-pvc--*--thin' -exec false {} + 2>/dev/null"

__stage 'Ensuring that the second pod is still writing to the volume...'
ensure_pod_is_writing 1

__stage 'Deleting the second pod...'
kubectl delete pod test-pod-1 --timeout=30s

__stage 'Deleting volume...'
kubectl delete pvc test-pvc --timeout=30s
