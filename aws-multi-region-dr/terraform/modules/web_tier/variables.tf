variable "project" {
  type = string
}

variable "name" {
  description = "Short suffix for this region, e.g. east or west"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "desired" {
  type = number
}
