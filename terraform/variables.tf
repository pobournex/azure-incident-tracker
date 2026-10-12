variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region. Pick one where the VM size below is available to your subscription (check with az vm list-skus)."
  type        = string
  default     = "centralus"
}

variable "environment" {
  description = "Environment tag and name suffix."
  type        = string
  default     = "demo"
}

variable "allowed_ssh_cidr" {
  description = "Optional standing SSH allow rule for one IP in CIDR form. Leave empty (the default) to keep SSH closed; the deploy workflow opens a temporary rule instead."
  type        = string
  default     = ""

  validation {
    condition     = var.allowed_ssh_cidr == "" || (can(cidrhost(var.allowed_ssh_cidr, 0)) && var.allowed_ssh_cidr != "0.0.0.0/0")
    error_message = "allowed_ssh_cidr must be empty or a valid CIDR, and must not be 0.0.0.0/0."
  }
}

variable "admin_username" {
  description = "Admin user created on every VM."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key installed for the admin user. Password login is disabled."
  type        = string
}

variable "shutdown_time" {
  description = "Daily auto-shutdown time in HHMM (24h) in shutdown_timezone. Stops compute billing overnight."
  type        = string
  default     = "2300"
}

variable "shutdown_timezone" {
  description = "Windows-style timezone name for the shutdown schedule."
  type        = string
  default     = "Central Standard Time"
}

variable "public_ip_for_private_tier" {
  description = <<-EOT
    Give the app and db VMs a public IP (inbound still blocked by NSG except SSH from allowed_ssh_cidr).
    Needed for apt/pip because new VNets may not provide default outbound internet access.
    The production alternative is a NAT gateway, which costs far more than this lab needs.
  EOT
  type        = bool
  default     = true
}

variable "vms" {
  description = "VMs to create, keyed by name. 'subnet' is 'web' or 'private'."
  type = map(object({
    tier   = string
    size   = string
    subnet = string
  }))
  default = {
    web = { tier = "web", size = "Standard_B2ats_v2", subnet = "web" }
    app = { tier = "app", size = "Standard_B2ats_v2", subnet = "private" }
    db  = { tier = "db", size = "Standard_B2ats_v2", subnet = "private" }
  }
}
