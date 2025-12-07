output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "vm_public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "sp_id" {
  value = data.azurerm_client_config.current.client_id
  description = "Client ID of the user/SP running Terraform"
}

output "sp_client_id" {
  value = azuread_application.lab_app.client_id
}

output "sp_client_secret" {
  value     = azuread_service_principal_password.lab_sp_password.value
  sensitive = true
}

output "sp_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "vnet_name" {
  value = azurerm_virtual_network.vnet.name
}

output "private_dns_zone_name" {
  value = azurerm_private_dns_zone.dns.name
}

output "key_vault_private_ip" {
  value = azurerm_private_endpoint.pe.private_service_connection[0].private_ip_address
}

output "vnet_link_name" {
  value = try(azurerm_private_dns_zone_virtual_network_link.link[0].name, "")
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.vm.name
  description = "Name of the agent virtual machine"
}

# Lab 3: Custom DNS Server Outputs
output "dns_server_ip" {
  value = var.lab_scenario == "dns_exercise3" && var.custom_dns_image_id != "" ? azurerm_network_interface.dns_nic[0].private_ip_address : null
  description = "Private IP address of the custom DNS server (Lab 3 only)"
}

output "dns_server_vm_name" {
  value = var.lab_scenario == "dns_exercise3" && var.custom_dns_image_id != "" ? azurerm_linux_virtual_machine.dns_vm[0].name : null
  description = "Name of the custom DNS server VM (Lab 3 only)"
}

output "vnet_dns_servers" {
  value = azurerm_virtual_network.vnet.dns_servers
  description = "Configured DNS servers on the VNet"
}
