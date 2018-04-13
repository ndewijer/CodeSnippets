#grab R53 zone info based on zonename given to module
data "aws_route53_zone" "dns_zone" {
  name = "${var.dns_zone}."
}
