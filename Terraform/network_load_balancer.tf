variable "ElasticIP-LB" { 
  default = "eipalloc-38440216"
}

resource "aws_lb" "Splunk-LB" {
  name = "Splunk-Loadbalancer"
  load_balancer_type = "network"
  #subnets = ["${aws_subnet.eu-west-2a-public.id}"]
  internal = false

  subnet_mapping {
    subnet_id = "${aws_subnet.eu-west-2a-public.id}"
    allocation_id = "${var.ElasticIP-LB}"
  }
}

resource "aws_lb_target_group" "Splunk-LB-indexer-targetgroup" {
  vpc_id = "${aws_vpc.nick.id}"
  name = "Splunk-LB-indexer-targetgroup"
  protocol = "TCP"
  port = "22"
  target_type = "instance"
}

resource "aws_lb_listener" "Splunk-LB-22" {
  load_balancer_arn = "${aws_lb.Splunk-LB.arn}"
  port = "22"
  protocol = "TCP"

  default_action {
    target_group_arn = "${aws_lb_target_group.Splunk-LB-indexer-targetgroup.arn}"
    type             = "forward"
  }
} 

resource "aws_lb_listener" "Splunk-LB-8000" {
  load_balancer_arn = "${aws_lb.Splunk-LB.arn}"
  port = "8000"
  protocol = "TCP"

  default_action {
    target_group_arn = "${aws_lb_target_group.Splunk-LB-indexer-targetgroup.arn}"
    type             = "forward"
  }
} 

resource "aws_lb_listener" "Splunk-LB-9997" {
  load_balancer_arn = "${aws_lb.Splunk-LB.arn}"
  port = "9997"
  protocol = "TCP"

  default_action {
    target_group_arn = "${aws_lb_target_group.Splunk-LB-indexer-targetgroup.arn}"
    type             = "forward"
  }
} 

resource "aws_lb_target_group_attachment" "Splunk-LB-Attachment-splunk-indexer-01" {
  target_id = "${aws_instance.splunk-indexer-01.id}"
  target_group_arn = "${aws_lb_target_group.Splunk-LB-indexer-targetgroup.arn}"
  port = 22
}