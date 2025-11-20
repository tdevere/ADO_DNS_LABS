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
