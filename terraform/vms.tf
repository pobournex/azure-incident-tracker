locals {
  # Web VMs always get a public IP; the private tier only if the toggle is on.
  vms_with_public_ip = {
    for name, vm in var.vms : name => vm
    if vm.subnet == "web" || var.public_ip_for_private_tier
  }
}

resource "azurerm_public_ip" "vm" {
  for_each            = local.vms_with_public_ip
  name                = "pip-${each.key}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(local.tags, { tier = each.value.tier })
}

resource "azurerm_network_interface" "vm" {
  for_each            = var.vms
  name                = "nic-${each.key}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = merge(local.tags, { tier = each.value.tier })

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.tier[each.value.subnet].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = try(azurerm_public_ip.vm[each.key].id, null)
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = var.vms
  name                            = "vm-${each.key}-${local.name_suffix}"
  computer_name                   = each.key
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = each.value.size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  tags                            = merge(local.tags, { tier = each.value.tier })

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# Stop (deallocate) every VM nightly so forgotten VMs stop billing for compute.
resource "azurerm_dev_test_global_vm_shutdown_schedule" "vm" {
  for_each              = var.vms
  virtual_machine_id    = azurerm_linux_virtual_machine.vm[each.key].id
  location              = azurerm_resource_group.main.location
  enabled               = true
  daily_recurrence_time = var.shutdown_time
  timezone              = var.shutdown_timezone

  notification_settings {
    enabled = false
  }
}
