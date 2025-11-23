provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.tags
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}
