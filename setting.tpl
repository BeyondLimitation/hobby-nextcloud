#cloud-config
packages:
  - [nfs-common]
runcmd:
  - mkdir /mnt/efs
  - mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${efs_mt_fqdn}:/ /mnt/efs
