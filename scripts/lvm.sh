#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

set -o errexit -o pipefail -o nounset -o xtrace

command=$1
backing_device_path=$2
lvm_vg_name=$3
lvm_thin_pool_lv_name=$4

export DM_DISABLE_UDEV=

# Usage: __run_ignoring_error <error_regex> <cmd...>
__run_ignoring_error() {
    local output
    output=$( "${@:2}" 2>&1 | tee /dev/stderr ) || grep -iE "$1" <<< "$output"
}

# Run LVM commands outside container because they are designed for a single
# system-wide instance and do not support containers.
__lvm() {
    nsenter --target 1 --all lvm "$@"
}

__lockstart() {
    __lvm vgchange \
        --devices "$backing_device_path" \
        --lock-start \
        "$lvm_vg_name"
}

# ensure LVM VG lockspace is started (oftentimes it first fails but works on the
# second try; TODO: figure out why)
__lockstart || __lockstart

case "${command}" in
    lockstart)
        ;;

    create-empty)
        lvm_thin_lv_name=$5
        size_bytes=$6

        # Start off with a smallish thin pool to avoid wasting space

        max_thin_pool_start_bytes=$((1024 * 1024 * 1024))
        thin_pool_size=$((max_thin_pool_start_bytes))
        if [ "$size_bytes" -lt $((max_thin_pool_start_bytes / 2)) ]; then
                thin_pool_size=$((size_bytes * 2))
        fi

        # create LVM thin *pool* LV

        __run_ignoring_error "already exists in volume group" \
            __lvm lvcreate \
            --devices "$backing_device_path" \
            --activate n \
            --type thin-pool \
            --name "$lvm_thin_pool_lv_name" \
            --size "${thin_pool_size}b" \
            "$lvm_vg_name"

	    # create LVM thin LV

        __run_ignoring_error "already exists in volume group" \
            __lvm lvcreate \
            --devices "$backing_device_path" \
            --type thin \
            --name "$lvm_thin_lv_name" \
            --thinpool "$lvm_thin_pool_lv_name" \
            --virtualsize "${size_bytes}b" \
            "$lvm_vg_name"

        # deactivate LVM thin LV (`--activate n` has no effect on `lvcreate
        # --type thin`)

        __lvm lvchange \
            --devices "$backing_device_path" \
            --activate n \
            "$lvm_vg_name/$lvm_thin_lv_name"
        ;;

    create-snapshot)
        lvm_thin_lv_name=$5
        lvm_source_thin_lv_name=$6

        # create snapshot LVM thin LV

        __run_ignoring_error "already exists in volume group" \
            __lvm lvcreate \
            --devices "$backing_device_path" \
            --name "$lvm_thin_lv_name" \
            --snapshot \
            --setactivationskip n \
            "$lvm_vg_name/$lvm_source_thin_lv_name"

        # deactivate LVM thin LV (`--activate n` has no effect on `lvcreate
        # --type thin`)

        __lvm lvchange \
            --devices "$backing_device_path" \
            --activate n \
            "$lvm_vg_name/$lvm_thin_lv_name"
        ;;

    delete)
        lvm_thin_lv_name=$5

	    # remove LVM thin LV

        __run_ignoring_error "failed to find logical volume" \
            __lvm lvremove \
            --devices "$backing_device_path" \
            "$lvm_vg_name/$lvm_thin_lv_name"

	    # remove LVM thin *pool* LV if there are no more thin LVs

        __run_ignoring_error "failed to find logical volume|removing pool \S+ will remove" \
            __lvm lvremove \
            --devices "$backing_device_path" \
            "$lvm_vg_name/$lvm_thin_pool_lv_name"
        ;;

    activate-pool)
        # activate LVM thin *pool* LV

        __lvm lvchange \
            --devices "$backing_device_path" \
            --activate ey \
            "$lvm_vg_name/$lvm_thin_pool_lv_name"
        ;;

    deactivate-pool)
        # deactivate LVM thin *pool* LV

        __lvm lvchange \
            --devices "$backing_device_path" \
            --activate n \
            "$lvm_vg_name/$lvm_thin_pool_lv_name"
        ;;

    activate)
        lvm_thin_lv_name=$5

        # activate LVM thin LV

        __lvm lvchange \
            --devices "$backing_device_path" \
            --activate ey \
            --monitor y \
            "$lvm_vg_name/$lvm_thin_lv_name"
        ;;

    deactivate)
        lvm_thin_lv_name=$5

        # deactivate LVM thin LV

        __lvm lvchange \
            --devices "$backing_device_path" \
            --activate n \
            "$lvm_vg_name/$lvm_thin_lv_name"
        ;;
esac
