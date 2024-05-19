// SPDX-License-Identifier: Apache-2.0

package node

import (
	"context"
	"slices"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"k8s.io/apimachinery/pkg/types"

	"gitlab.com/kubesan/kubesan/api/v1alpha1"
	"gitlab.com/kubesan/kubesan/internal/common/config"
	kubesanslices "gitlab.com/kubesan/kubesan/internal/common/slices"
	"gitlab.com/kubesan/kubesan/internal/csi/common/validate"
)

func (s *NodeServer) NodeStageVolume(ctx context.Context, req *csi.NodeStageVolumeRequest) (*csi.NodeStageVolumeResponse, error) {
	// validate request

	if req.VolumeId == "" {
		return nil, status.Errorf(codes.InvalidArgument, "must specify volume id")
	}

	if err := validate.ValidateVolumeCapability(req.VolumeCapability); err != nil {
		return nil, err
	}

	// attach volume to local node

	volume := &v1alpha1.Volume{}
	if err := s.client.Get(ctx, types.NamespacedName{Name: req.VolumeId}, volume); err != nil {
		return nil, err
	}

	if !slices.Contains(volume.Spec.AttachToNodes, config.LocalNodeName) {
		volume.Spec.AttachToNodes = kubesanslices.AppendUnique(volume.Spec.AttachToNodes, config.LocalNodeName)

		if err := s.client.Update(ctx, volume); err != nil {
			return nil, err
		}
	}

	// wait until volume is attached to local node

	err := s.client.WatchVolumeUntil(ctx, volume, func() bool {
		return slices.Contains(volume.Status.AttachedToNodes, config.LocalNodeName)
	})
	if err != nil {
		return nil, err
	}

	// success

	return &csi.NodeStageVolumeResponse{}, nil
}

func (s *NodeServer) NodeUnstageVolume(ctx context.Context, req *csi.NodeUnstageVolumeRequest) (*csi.NodeUnstageVolumeResponse, error) {
	// validate request

	if req.VolumeId == "" {
		return nil, status.Errorf(codes.InvalidArgument, "must specify volume id")
	}

	if req.StagingTargetPath == "" {
		return nil, status.Errorf(codes.InvalidArgument, "must specify staging target path")
	}

	// detach volume from local node

	volume := &v1alpha1.Volume{}
	if err := s.client.Get(ctx, types.NamespacedName{Name: req.VolumeId}, volume); err != nil {
		return nil, err
	}

	if slices.Contains(volume.Spec.AttachToNodes, config.LocalNodeName) {
		volume.Spec.AttachToNodes = kubesanslices.RemoveAll(volume.Spec.AttachToNodes, config.LocalNodeName)

		if err := s.client.Update(ctx, volume); err != nil {
			return nil, err
		}
	}

	// wait until volume is detached from local node

	err := s.client.WatchVolumeUntil(ctx, volume, func() bool {
		return !slices.Contains(volume.Status.AttachedToNodes, config.LocalNodeName)
	})
	if err != nil {
		return nil, err
	}

	// success

	return &csi.NodeUnstageVolumeResponse{}, nil
}

// // Mount a file system from a device and format it, if necessary.
// func (s *NodeServer) formatAndMount(source string, target string, fstype string, mountFlags []string) error {
// 	f := mount.NewSafeFormatAndMount(s.mounter, s.exec)

// 	// already mounted?

// 	if sure, err := f.IsMountPoint(target); sure && err == nil {
// 		return nil
// 	}

// 	// format, if necessary, and then mount

// 	if err := f.FormatAndMountSensitive(source, target, fstype, nil, mountFlags); err != nil {
// 		return status.Errorf(codes.Internal, "format and mount failed source=%s target=%s fstype=%s: %v", source, target, fstype, err)
// 	}

// 	// cloned volumes may be larger than the file system, so resize

// 	resizeFs := mount.NewResizeFs(s.exec)
// 	needResize, err := resizeFs.NeedResize(source, target)
// 	if err != nil {
// 		return status.Errorf(codes.Internal, "failed to determine whether to resize source=%s target=%s fstype=%s: %v", source, target, fstype, err)
// 	}
// 	if needResize {
// 		_, err := resizeFs.Resize(source, target)
// 		if err != nil {
// 			return status.Errorf(codes.Internal, "failed to resize source=%s target=%s fstype=%s: %v", source, target, fstype, err)
// 		}
// 	}
// 	return nil
// }

// func (s *NodeServer) NodeStageVolume(ctx context.Context, req *csi.NodeStageVolumeRequest) (*csi.NodeStageVolumeResponse, error) {
// 	// TODO: Validate request.
// 	// TODO: Must enforce access modes ourselves; check the CSI spec.

// 	// validate request

// 	if err := validate.ValidateVolumeCapability(req.VolumeCapability); err != nil {
// 		return nil, err
// 	}

// 	blob, err := blobs.BlobFromString(req.VolumeId)
// 	if err != nil {
// 		return nil, err
// 	}

// 	// attach blob on current node

// 	_, path, err := s.BlobManager.AttachBlob(ctx, blob, &config.LocalNodeName, "staged")
// 	if err != nil {
// 		return nil, err
// 	}

// 	if mount := req.VolumeCapability.GetMount(); mount != nil {
// 		// format and mount (Filesystem volumes only)
// 		if err := s.formatAndMount(path, req.StagingTargetPath, mount.FsType, mount.MountFlags); err != nil {
// 			return nil, err
// 		}
// 	} else {
// 		// create symlink to device for NodePublishVolume() (block volumes only)
// 		err = util.Symlink(path, req.StagingTargetPath)
// 		if err != nil {
// 			return nil, err
// 		}
// 	}

// 	// success

// 	resp := &csi.NodeStageVolumeResponse{}
// 	return resp, nil
// }

// func (s *NodeServer) NodeUnstageVolume(ctx context.Context, req *csi.NodeUnstageVolumeRequest) (*csi.NodeUnstageVolumeResponse, error) {
// 	// validate request

// 	blob, err := blobs.BlobFromString(req.VolumeId)
// 	if err != nil {
// 		return nil, err
// 	}

// 	// unmount file system, if necessary

// 	targetPath := req.GetStagingTargetPath()
// 	if err := mount.CleanupMountPoint(targetPath, s.mounter, true); err != nil {
// 		return nil, status.Errorf(codes.Internal, "failed to clean up mount point %s for volume %s: %v", targetPath, req.VolumeId, err)
// 	}
// 	// detach blob from current node

// 	err = s.BlobManager.DetachBlob(ctx, blob, config.LocalNodeName, "staged")
// 	if err != nil {
// 		return nil, err
// 	}

// 	// success

// 	resp := &csi.NodeUnstageVolumeResponse{}
// 	return resp, nil
// }
