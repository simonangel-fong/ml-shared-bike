# variables.tf

variable "env" {
  default = "dev"
}

variable "data_scientists" {
  default = {
    Alice = "alice"
    # Bob   = "bob"
  }
}
