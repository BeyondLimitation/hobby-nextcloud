#cloud-config
packages:
  - [nfs-common]
runcmd:
  - mkdir /mnt/efs/${efs_mt_fqdn}
