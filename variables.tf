variable "region" {
  type        = string
  description = "Region"
}

variable "azs" {
  type        = list(string)
  description = "가용 영역의 목록"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC의 CIDR 값"
}

variable "public_subnets" {
  type        = list(string)
  description = "VPC의 Public Subnet들. 인터넷 접속 가능"
}

variable "private_subnets" {
  type        = list(string)
  description = "VPC의 Private Subnet들."
}

variable "mon_vpc_cidr" {
  type        = string
  description = "VPC 'moniter-terraform'의 CIDR"
}

variable "mon_public_subnets" {
  type        = list(string)
  description = "VPC 'monitering-terraform'를 위한 Public Subnet"
}

variable "mon_private_subnets" {
  type        = list(string)
  description = "VPC 'monitering-terraform'를 위한 Private Subnet"
}

