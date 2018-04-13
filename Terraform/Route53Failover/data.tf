data "aws_route53_zone" "dns_zone" {
  name = "${var.dns_zone}."
}
