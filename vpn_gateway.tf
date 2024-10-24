##
## Variables
##
variable "vpn_gateway_ubuntu_version" {
  description = "Ubuntu version to use for the runner. For example, 22.04"
  type        = string
  default     = "22.04"
}

variable "vpn_gateway_ubuntu_ami_version" {
  description = "Specific version of the Ubuntu AMI to use for the runner. For example, 20220616"
  type        = string
  default     = "latest"
}

variable "vpn_gateway_ubuntu_ami_owner" {
  description = "Owner of the Ubuntu AMI to use for the runner. For example, 099720109477"
  type        = list(string)
  default     = ["099720109477"]
}

variable "vpn_gateway_instance_type" {
  description = "Instance type to use for the runner."
  type        = string
  default     = "m8g.medium"
}

variable "vpn_gateway_volume_size" {
  description = "Volume size to use for the VPN gateway. In gigabytes."
  type        = number
  default     = 16
}

variable "vpn_gateway_data_volume_size" {
  description = "Volume size to use for the VPN gateway data dir. In gigabytes."
  type        = number
  default     = 4
}

variable "vpn_gateway_volume_throughput" {
  description = "Volume throughput to use for the runner."
  type        = number
  default     = null
}

variable "vpn_gateway_volume_iops" {
  description = "Volume IOPS to use for the runner."
  type        = number
  default     = null
}

variable "vpn_gateway_ssm_enabled" {
  description = "Whether to enable SSM on the runner."
  type        = bool
  default     = true
}

variable "vpn_gateway_webui_ip_whitelist" {
  description = "Whitelisted IPs that can connect to WG-Easy WebUI."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "vpn_gateway_allowed_ips" {
  description = "Allowed IPs for the WireGuard VPN."
  type        = string
  default     = "0.0.0.0/0"
}

variable "vpn_gateway_host" {
  description = "Domain for the VPN gateway."
  type        = string
  default     = ""
}

variable "vpn_gateway_email" {
  description = "Email for certificate generation."
  type        = string
}

##
## Resources
##

#
# AMI
#
data "aws_ec2_instance_type" "vpn_gateway" {
  instance_type = var.vpn_gateway_instance_type
}

data "aws_ami" "vpn_gateway" {
  most_recent = true

  filter {
    name = "name"
    values = [
      var.vpn_gateway_ubuntu_ami_version == "latest" ? "ubuntu/images/*${var.vpn_gateway_ubuntu_version}*-server-*" : "ubuntu/images/*${var.vpn_gateway_ubuntu_version}*-server-${var.vpn_gateway_ubuntu_ami_version}"
    ]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = data.aws_ec2_instance_type.vpn_gateway.supported_architectures
  }

  owners = var.vpn_gateway_ubuntu_ami_owner
}

#
# VPN Gateway Security Group
#
resource "aws_security_group" "vpn_gateway" {
  name   = "vpn-gateway-sg"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name" = "vpn-gateway-sg"
  }
}

resource "aws_security_group_rule" "wg_easy_webui_http" {
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = var.vpn_gateway_webui_ip_whitelist
  description = "WG-Easy WebUI"

  security_group_id = aws_security_group.vpn_gateway.id
}

resource "aws_security_group_rule" "wg_easy_webui_https_tcp" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = var.vpn_gateway_webui_ip_whitelist
  description = "WG-Easy WebUI"

  security_group_id = aws_security_group.vpn_gateway.id
}

resource "aws_security_group_rule" "wg_easy_webui_https_udp" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "udp"
  cidr_blocks = var.vpn_gateway_webui_ip_whitelist
  description = "WG-Easy WebUI"

  security_group_id = aws_security_group.vpn_gateway.id
}

resource "aws_security_group_rule" "wg_easy_wireguard" {
  type        = "ingress"
  from_port   = 51820
  to_port     = 51820
  protocol    = "udp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "WireGuard VPN"

  security_group_id = aws_security_group.vpn_gateway.id
}

#
# VPN Gateway IAM
#
resource "aws_iam_role" "vpn_gateway_role" {
  name = "vpn-gateway_role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_instance_profile" "vpn_gateway_profile" {
  name = "vpn-gateway-instance-profile"
  role = aws_iam_role.vpn_gateway_role.name
}

resource "aws_iam_role_policy_attachment" "vpn_gateway_ssm_policy" {
  count      = var.vpn_gateway_ssm_enabled ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.vpn_gateway_role.name
}

resource "aws_eip" "vpn_gateway" {
  domain = "vpc"

  tags = {
    "Name" = "shared_vpn-gateway",
  }
}

resource "aws_eip_association" "vpn_gateway" {
  instance_id   = aws_instance.vpn_gateway.id
  allocation_id = aws_eip.vpn_gateway.id
}

resource "random_string" "vpn_ui_password" {
  length      = 32
  min_numeric = 4
  min_lower   = 8
  min_upper   = 8
  lower       = true
  upper       = true
  special     = false

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  vpn_gateway_user_data = <<-EOF
#cloud-config
apt:
  sources:
    docker.list:
      source: deb https://download.docker.com/linux/ubuntu $RELEASE stable
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88

packages:
  - docker-ce
  - docker-compose-plugin

package_update: false
package_upgrade: false

write_files:
  - path: /tmp/docker-compose.yml
    owner: root:root
    permissions: '0644'
    encoding: b64
    content: ${base64encode(templatefile(
  "${var.scripts_dir}/docker-compose.yml.tpl",
  {
    wg_email       = var.vpn_gateway_email,
    wg_host        = length(var.vpn_gateway_host) > 0 ? var.vpn_gateway_host : aws_eip.vpn_gateway.public_ip,
    wg_password    = replace(bcrypt(random_string.vpn_ui_password.result), "$", "$$"),
    wg_allowed_ips = var.vpn_gateway_allowed_ips,
}))}
  - path: /root/provision-ebs.sh
    owner: root:root
    permissions: '0744'
    encoding: b64
    content: ${filebase64("${var.scripts_dir}/provision-ebs.sh")}
  - path: /etc/sysctl.d/10-disable-ipv6.conf
    permissions: 0644
    owner: root
    content: |
      net.ipv6.conf.all.disable_ipv6=1
      net.ipv6.conf.default.disable_ipv6=1
      net.ipv6.conf.lo.disable_ipv6=1
  - path: /etc/sysctl.d/20-maxsockbuf.conf
    permissions: 0644
    owner: root
    content: |
      net.core.wmem_max=7500000

runcmd:
  - systemctl restart systemd-sysctl
  - /root/provision-ebs.sh /dev/nvme1n1 ext4 /data
  - mkdir -p /data/wg-easy
  - mv /tmp/docker-compose.yml /data/wg-easy/docker-compose.yaml
  - cd /data/wg-easy && docker compose up --detach --quiet-pull
EOF
}

resource "aws_ebs_volume" "vpn_gateway_data" {
  availability_zone = aws_subnet.public[keys(aws_subnet.public)[0]].availability_zone
  size              = var.vpn_gateway_data_volume_size
  type              = "gp3"

  tags = {
    Name = "${var.project_name}_data"
  }
}

resource "aws_instance" "vpn_gateway" {
  ami                         = data.aws_ami.vpn_gateway.id
  instance_type               = var.vpn_gateway_instance_type
  subnet_id                   = aws_subnet.public[keys(aws_subnet.public)[0]].id
  vpc_security_group_ids      = [aws_security_group.vpn_gateway.id]
  associate_public_ip_address = true
  ebs_optimized               = true
  iam_instance_profile        = aws_iam_instance_profile.vpn_gateway_profile.id
  user_data_replace_on_change = true
  user_data                   = local.vpn_gateway_user_data

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.vpn_gateway_volume_size
    throughput            = var.vpn_gateway_volume_throughput
    iops                  = var.vpn_gateway_volume_iops
    delete_on_termination = true
    tags = {
      Name = "${var.project_name}_root"
    }
  }

  credit_specification {
    cpu_credits = "standard"
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [private_ip, ami]
  }

  depends_on = [
    aws_eip.vpn_gateway,
  ]

  tags = {
    "Name" = "${var.project_name}",
  }
}

resource "aws_volume_attachment" "vpn_gateway_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.vpn_gateway_data.id
  instance_id = aws_instance.vpn_gateway.id
}

output "vpn_gateway_public_ip" {
  description = "Public IP of the VPN Gateway"
  value       = aws_eip.vpn_gateway.public_ip
}

output "vpn_gateway_ui_url" {
  description = "WG-Easy WebUI"
  value       = "https://${length(var.vpn_gateway_host) > 0 ? var.vpn_gateway_host : aws_eip.vpn_gateway.public_ip}"
}

output "vpn_gateway_ui_password" {
  description = "Password for the WG-Easy WebUI"
  value       = random_string.vpn_ui_password.result
}
