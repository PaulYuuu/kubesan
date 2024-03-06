// SPDX-License-Identifier: Apache-2.0

package blobs

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"gitlab.com/subprovisioner/subprovisioner/pkg/subprovisioner/util/config"
	"gitlab.com/subprovisioner/subprovisioner/pkg/subprovisioner/util/k8s"
	"gitlab.com/subprovisioner/subprovisioner/pkg/subprovisioner/util/lvm"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
)

type BlobManager struct {
	clientset kubernetes.Interface
	crdRest   rest.Interface
}

func NewBlobManager() (*BlobManager, error) {
	restConfig, err := rest.InClusterConfig()
	if err != nil {
		return nil, err
	}

	clientset, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		return nil, err
	}

	crdRestConfig := rest.CopyConfig(restConfig)
	crdRestConfig.GroupVersion = &schema.GroupVersion{Group: config.Domain, Version: "v1alpha1"}
	crdRestConfig.NegotiatedSerializer = scheme.Codecs.WithoutConversion()
	crdRestConfig.APIPath = "/apis"
	if crdRestConfig.UserAgent == "" {
		crdRestConfig.UserAgent = rest.DefaultKubernetesUserAgent()
	}

	crdRest, err := rest.RESTClientFor(crdRestConfig)
	if err != nil {
		return nil, err
	}

	return &BlobManager{
		clientset: clientset,
		crdRest:   crdRest,
	}, nil
}

func (bm *BlobManager) Clientset() kubernetes.Interface {
	return bm.clientset
}

// This method may be called from any node, and fails if the blob does not exist.
func (bm *BlobManager) GetBlobSize(ctx context.Context, blob *Blob) (int64, error) {
	output, err := lvm.Command(
		ctx,
		"lvs",
		"--devices", blob.pool.backingDevicePath,
		"--options", "lv_size",
		"--units", "b",
		"--nosuffix",
		"--noheadings",
		fmt.Sprintf("%s/%s", config.LvmVgName, blob.lvmThinLvName()),
	)
	if err != nil {
		return -1, status.Errorf(codes.Internal, "failed to get size of LVM LV: %s: %s", err, output)
	}

	sizeStr := strings.TrimSpace(output)

	size, err := strconv.ParseInt(sizeStr, 0, 64)
	if err != nil {
		return -1, status.Errorf(codes.Internal, "failed to get size of LVM LV: %s: %s", err, sizeStr)
	}

	return size, nil
}

func (bm *BlobManager) atomicUpdateBlobPoolCrd(ctx context.Context, poolName string, f func(*blobPoolCrdSpec) error) error {
	crd := blobPoolCrd{ObjectMeta: metav1.ObjectMeta{Name: poolName}}

	err := k8s.AtomicUpdate(
		ctx, bm.crdRest, "blobpools", &crd,
		func(crd *blobPoolCrd) error { return f(&crd.Spec) },
	)
	if err != nil {
		return status.Errorf(codes.Internal, "failed to update BlobPool: %s", err)
	}

	return nil
}
