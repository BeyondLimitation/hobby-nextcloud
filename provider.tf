terraform {
  backend "remote" {
    organization = "Lee-personal-project"
    workspaces {
      name = "hobby-nextcloud"
    }
  }
}

provider "aws" {
  region = var.region
}