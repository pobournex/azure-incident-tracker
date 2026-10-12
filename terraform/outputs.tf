output "resource_group" {
  description = "Delete this resource group to remove everything (or run terraform destroy)."
  value       = azurerm_resource_group.main.name
}

output "vms" {
  description = "Per-VM details used to generate the Ansible inventory."
  value = {
    for name, vm in var.vms : name => {
      tier       = vm.tier
      private_ip = azurerm_network_interface.vm[name].private_ip_address
      public_ip  = try(azurerm_public_ip.vm[name].ip_address, null)
    }
  }
}

output "app_url" {
  description = "Public URL of the web tier."
  value       = "http://${azurerm_public_ip.vm["web"].ip_address}"
}
