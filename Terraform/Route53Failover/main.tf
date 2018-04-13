# Route 53
resource "aws_route53_health_check" "alb_test" {
  fqdn              = "${aws_route53_record.production.fqdn}"
  type              = "${var.type}"                           # can be HTTP, HTTPS, TCP. Use HTTP_STR_MATCH or HTTPS_STR_MATCH when combined with search_string
  port              = "${var.port}"
  resource_path     = "${var.resource_path}"
  failure_threshold = "${var.failure_threshold}"
  request_interval  = "${var.request_interval}"

  search_string = "${var.stringmatch}"

  tags {
    Name = "${var.domain}-alb-healthcheck"
  }
}

resource "aws_route53_record" "production" {
  zone_id = "${data.aws_route53_zone.dns_zone.zone_id}"
  name    = "${var.domain}-production"
  type    = "A"

  alias {
    name                   = "${var.production_alb_name}"
    zone_id                = "${var.production_alb_zone}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "fallback" {
  zone_id = "${data.aws_route53_zone.dns_zone.zone_id}"
  name    = "${var.domain}-fallback"
  type    = "A"

  alias {
    name                   = "${var.failover_alb_name}"
    zone_id                = "${var.failover_alb_zone}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "failover_production" {
  zone_id         = "${data.aws_route53_zone.dns_zone.zone_id}"
  name            = "${var.domain}"
  type            = "CNAME"
  ttl             = "60"
  records         = ["${aws_route53_record.production.fqdn}"]
  health_check_id = "${aws_route53_health_check.alb_test.id}"
  set_identifier  = "${var.domain}_production"

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "failover_fallback" {
  zone_id        = "${data.aws_route53_zone.dns_zone.zone_id}"
  name           = "${var.domain}"
  type           = "CNAME"
  ttl            = "60"
  records        = ["${aws_route53_record.fallback.fqdn}"]
  set_identifier = "${var.domain}_fallback"

  failover_routing_policy {
    type = "SECONDARY"
  }
}
