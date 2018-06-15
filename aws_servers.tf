variable "aws_access_key" {
#    default = ""
}

variable "aws_secret_key" {
#    default = ""
}

variable "server_count"{
#    default = "2"
}

variable "management_ip" {
#    default = ""
}

/* Our root SSH key pair is created by the wrapper script. */
resource "aws_key_pair" "root" {
    key_name = "root-key"
    public_key = "${file("id_rsa_example.pub")}"
}

variable "agg-zones" {
    default = {
        zone0 = "eu-west-1a"
        zone1 = "eu-west-1b"
        zone2 = "eu-west-1c"
    }
}

variable "agg-cidr_blocks" {
    default = {
        zone0 = "10.11.1.0/24"
        zone1 = "10.11.2.0/24"
        zone2 = "10.11.3.0/24"
    }
}


/* We'll be using AWS for provisioning of the instances,
   so we'll set "aws" as a provider. */

provider "aws" {
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
    region = "eu-west-1"
}


/* Set up a VPC with a private /16 range. */

resource "aws_vpc" "agg" {
    cidr_block = "10.11.0.0/16"

    tags {
        Name = "agg VPC"
    }
}


/* We'll set up two subnets in different availability zones for
   high availability in case an AZ fails.  */

resource "aws_subnet" "agg" {
    depends_on = ["aws_vpc.agg"]
    vpc_id = "${aws_vpc.agg.id}"
    cidr_block = "${lookup(var.agg-cidr_blocks, "zone${count.index}")}"
    availability_zone = "${lookup(var.agg-zones, "zone${count.index}")}"
    count = "${var.server_count}"
    map_public_ip_on_launch = true
#    lifecycle {
#    	create_before_destroy = true
#    }
}


/* We'll need an Internet gateway, a routing table and routing
   table associations for both of our subnets. */

resource "aws_internet_gateway" "agg" {
  depends_on = ["aws_vpc.agg"]
  vpc_id = "${aws_vpc.agg.id}"
}

resource "aws_route_table" "agg" {
  depends_on = ["aws_vpc.agg","aws_internet_gateway.agg"]
  vpc_id = "${aws_vpc.agg.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.agg.id}"
  }
}

resource "aws_route_table_association" "agg" {
    depends_on = ["aws_subnet.agg", "aws_route_table.agg"]
    subnet_id = "${element(aws_subnet.agg.*.id, "${count.index}")}"
    route_table_id = "${aws_route_table.agg.id}"
    count = "${var.server_count}"
    lifecycle {
        create_before_destroy = true
    }
}


/* Security group for the load balancer. We'll open port 80/tcp
   to the world, and port 22/tcp to our management IP. We'll allow
   everything outbound. */

resource "aws_security_group" "agg-lb" {
    depends_on = ["aws_vpc.agg","aws_subnet.agg"]
    name = "agg-lb"
    description = "Security group for the load balancer"
    vpc_id = "${aws_vpc.agg.id}"
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["${var.management_ip}/32"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}


/* Security group for the app nodes. We'll allow 8484/tcp from our load
   balancer, and 22/tcp from the management IP. */

resource "aws_security_group" "agg-app" {
    depends_on = ["aws_security_group.agg-lb","aws_vpc.agg","aws_subnet.agg"]
    name = "agg-app"
    description = "Security group for the app instances"
    vpc_id = "${aws_vpc.agg.id}"
    ingress {
        from_port = 8484
        to_port = 8484
        protocol = "tcp"
        security_groups = ["${aws_security_group.agg-lb.id}"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["${var.management_ip}/32"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}



resource "aws_alb" "agg-lb" {
    depends_on = ["aws_subnet.agg","aws_security_group.agg-lb"]
    name               = "example-lb"
    internal           = false
    load_balancer_type = "application"
 ### Commented to avoid problems with terraform destroy
 #   enable_deletion_protection = true
 #
    subnets = ["${aws_subnet.agg.*.id}"]

    security_groups = ["${aws_security_group.agg-lb.*.id}"]
}


resource "aws_alb_target_group" "alb_target_group" {  
    name     = "alb-target-group" 
    port     = 8484  
    protocol = "HTTP"  
    vpc_id   = "${aws_vpc.agg.id}"   
    tags {    
    	name = "alb-target-group"   
    }     
    health_check {    
  	healthy_threshold   = 3    
  	unhealthy_threshold = 10    
  	timeout             = 5    
  	interval            = 10    
   	path                = "/actuator/health"    
   	port                = 8484  
  }
}

resource "aws_alb_listener" "alb_listener" { 
  	load_balancer_arn = "${aws_alb.agg-lb.arn}"
  	port              = 80 

  default_action {   
  	target_group_arn = "${aws_alb_target_group.alb_target_group.arn}"
  	type             = "forward" 
  }
}


/* The app nodes are also t2.micros running Amazon AMI
   for simplicity. We place the app nodes in different AZs. */

resource "aws_instance" "agg-app" {
    ami = "ami-ca0135b3"
    depends_on = ["aws_subnet.agg","aws_security_group.agg-app"]
    instance_type = "t2.micro"
    count = "${var.server_count}"
    tags {
        Name = "node-app${count.index}"
    }
    
/*  To ensure there is no downtime, we create the new servers before destroying the old ones  */
    lifecycle {
        create_before_destroy = true
    }

    subnet_id = "${element(aws_subnet.agg.*.id, count.index)}"
    associate_public_ip_address = true

    key_name = "${aws_key_pair.root.key_name}"  
    vpc_security_group_ids = ["${aws_security_group.agg-app.id}"]

  provisioner "file" {
    source      = "./chef.tar.gz"
    destination = "/tmp/chef.tar.gz"
    connection {
	    type = "ssh"
	    agent = false
            user = "ec2-user"
            private_key = "${file("id_rsa_example")}"
            timeout = "200s"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "curl -LO https://www.chef.io/chef/install.sh && sudo bash ./install.sh",
      "cd /tmp ; tar -xvzf chef.tar.gz",
      "cd chef ; sudo chef-solo -c solo.rb -o app_server",
      "chmod +x check_health.sh ; ./check_health.sh ${self.public_ip}:8484/actuator/health"	
    ]
    connection {
            user = "ec2-user"
	    private_key = "${file("id_rsa_example")}"
            timeout = "60s"
    }
  }
  /* Script to check that the app is up and running, for create_before_destroy lifecycle, done lines up in remote-exec */ 
#  provisioner "local-exec" {
#    command = "cd /tmp/chef ; chmod +x check_health.sh ; ./check_health.sh localhost:8484/actuator/health"
#  }

}

#Instance Attachment
resource "aws_alb_target_group_attachment" "svc_physical_external" {
    depends_on = ["aws_internet_gateway.agg", "aws_subnet.agg"]
    count = "${var.server_count}"
    target_group_arn = "${aws_alb_target_group.alb_target_group.arn}"
    target_id        = "${element(aws_instance.agg-app.*.id, count.index)}"
    port             = 8484
    lifecycle {
        create_before_destroy = true
    }
}


/* We'll need the load balancer address to verify it works */

output "lb-dns" {
    value = "${aws_alb.agg-lb.dns_name}"
}
