packer {
  required_version = ">= 1.9.0"
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_prefix" {
  type    = string
  default = "golden-ami-al2023"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "golden_ami" {
  ami_name      = "${var.ami_prefix}-${local.timestamp}"
  instance_type = var.instance_type
  region        = var.aws_region

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["137112412989"]
  }

  ssh_username = "ec2-user"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name        = "${var.ami_prefix}-${local.timestamp}"
    Environment = "production"
    ManagedBy   = "packer"
    Hardened    = "true"
  }
}

build {
  name    = "build-golden-ami"
  sources = ["source.amazon-ebs.golden_ami"]

  provisioner "ansible" {
    playbook_file = "./ansible-baseline-hardening.yml"
    extra_arguments = [
      "--extra-vars",
      "ansible_ssh_user=ec2-user",
      "-vv"
    ]
  }

  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
