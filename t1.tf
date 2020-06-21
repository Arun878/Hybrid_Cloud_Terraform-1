provider "aws"{
    region = "ap-south-1"
    profile = "default"
}

resource "tls_private_key" "accessKey" {
    algorithm = "RSA"
}

resource "aws_key_pair" "OSKey" {
    depends_on = [
        tls_private_key.accessKey,
    ]
    key_name = "RedHatOSKey"
    public_key = tls_private_key.accessKey.public_key_openssh
}

resource "local_file" "localKey" {

    depends_on = [
        tls_private_key.accessKey, aws_key_pair.OSKey,
    ]

    content = tls_private_key.accessKey.private_key_pem
    filename = "RedHatOSKey.pem"
    file_permission = "0400"
}

resource "aws_security_group" "allow_ports" {

    depends_on = [
        tls_private_key.accessKey, aws_key_pair.OSKey, local_file.localKey,
    ]

    name        = "allow_ports"
    description = "Allow inbound trafficon port 80"
    vpc_id      = "vpc-6ee4f906 "

    ingress {
        description = "Port_80"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "SSH Enable"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "allow_ports"
    }
}

resource "aws_instance" "RHEL8"{

    depends_on = [
        tls_private_key.accessKey, aws_key_pair.OSKey, 
        local_file.localKey, aws_security_group.allow_ports,
    ]

    ami = "ami-052c08d70def0ac62"
    instance_type = "t2.micro"
    key_name = aws_key_pair.OSKey.key_name
    security_groups = [ "allow_ports" ]
    availability_zone = "ap-south-1a"

    tags = {
        Name = "MyTerraOs"
    }
}

resource "aws_ebs_volume" "RHEL8_Volume" {

    depends_on = [
        tls_private_key.accessKey, aws_key_pair.OSKey, local_file.localKey,
         aws_security_group.allow_ports, aws_instance.RHEL8,
    ]

    availability_zone = "ap-south-1a"
    size = 1

    tags = {
        Name = "MyTerraVolumne"
    }
}

resource "aws_volume_attachment" "vol_attach" {

    depends_on = [
        tls_private_key.accessKey, aws_key_pair.OSKey, local_file.localKey, 
        aws_security_group.allow_ports, aws_instance.RHEL8, aws_ebs_volume.RHEL8_Volume,
    ]

    device_name = "/dev/sdh"
    volume_id = aws_ebs_volume.RHEL8_Volume.id
    instance_id = aws_instance.RHEL8.id
    force_detach = true
}

resource "aws_s3_bucket" "mybucket" {
    bucket = "arun-mywebdata"
    acl = "public-read"

    tags = {
        Name = "My WebData Bucket"
    }

    provisioner "local-exec" {
        command = "git clone https://github.com/Arun878/Hybrid_Cloud_T1.git web"
    }

    provisioner "local-exec" {
        when = destroy
        command = "rm -rf web"
    }
}

resource "aws_s3_bucket_object" "myobject" {

    depends_on = [
        aws_s3_bucket.mybucket, 
    ]

    bucket = aws_s3_bucket.mybucket.id
    key    = "sea.jpg"
    source = "web/image/sea.jpg"
    acl = "public-read"
}

locals {
    s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "myCloudFront" {
    origin {
        domain_name = aws_s3_bucket.mybucket.bucket_regional_domain_name
        origin_id   = local.s3_origin_id

    }
    enabled = true
    is_ipv6_enabled = true
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id

        forwarded_values {
            query_string = false

            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
        min_ttl                = 0
        default_ttl            = 3600
        max_ttl                = 86400
    }
    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }
    tags = {
        Name = "myCloudFront"
    }
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}

resource "null_resource" "null_res_cmd"{

    depends_on = [
        tls_private_key.accessKey, aws_key_pair.OSKey, local_file.localKey, aws_security_group.allow_ports, 
        aws_instance.RHEL8, aws_ebs_volume.RHEL8_Volume,
        aws_volume_attachment.vol_attach, aws_cloudfront_distribution.myCloudFront
    ]
    
    connection {
        type = "ssh"
        user = "ec2-user"
        host = aws_instance.RHEL8.public_ip
        private_key = tls_private_key.accessKey.private_key_pem
    }

    provisioner "remote-exec" {
        inline = [
            "sudo yum install git httpd -y",
            "sudo systemctl start httpd",
            "sudo systemctl enable httpd",
            "sudo mkfs.ext4 /dev/xvdh",
            "sudo mount /dev/xvdh /var/www/html",
            "sudo rm -rf /var/www/html/*",
            "sudo git clone https://github.com/Arun878/Hybrid_Cloud_T1.git /var/www/html/",
            "sudo setenforce 0",
            "sudo sed -i \"s/\\/image/http:\\/\\/${aws_cloudfront_distribution.myCloudFront.domain_name}/g\" /var/www/html/index.html"
        ]
    }
}
