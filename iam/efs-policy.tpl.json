{
  "Version" : "2012-10-17",
  "Id" : "terraform-nextcloud-policy",
  "Statement": [
	  {
		  "Sid": "Allow-All",
		  "Effect": "Allow",
		  "Principal": {
		  	"AWS": "${nextcloud-role}"
		  },
		  "Action": [
			  "elasticfilesystem:ClientRootAccess",
                          "elasticfilesystem:ClientWrite",
                          "elasticfilesystem:ClientMount"
		  ],
		  "Resource": "${efs-fs-arn}"
	  }
  ]
}
