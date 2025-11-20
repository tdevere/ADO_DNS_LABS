data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

resource "azuread_application" "lab_app" {
  display_name = "sp-dns-lab-${random_id.suffix.hex}"
  owners       = [data.azurerm_client_config.current.object_id]
  
  # Prevent Terraform from trying to manage this if it already exists and we can't delete it
  lifecycle {
    ignore_changes = [owners]
  }
}

resource "azuread_service_principal" "lab_sp" {
  client_id = azuread_application.lab_app.client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

resource "azuread_service_principal_password" "lab_sp_password" {
  service_principal_id = azuread_service_principal.lab_sp.id
}

resource "azurerm_role_assignment" "sp_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.lab_sp.object_id
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}-${random_id.suffix.hex}"
  location = var.location
}

# VNet and Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]
  
  # Lab 3: Custom DNS Misconfiguration
  dns_servers = var.lab_scenario == "dns_exercise3" ? ["10.1.2.50"] : []
}

resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.2.0/24"]
  
  # Enable Private Endpoint policies
  private_endpoint_network_policies = "Enabled"
}

# Key Vault
resource "azurerm_key_vault" "kv" {
  name                        = "kv-dns-lab-${random_id.suffix.hex}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  public_network_access_enabled = true # Needed for Terraform to seed secrets

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azuread_service_principal.lab_sp.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
    ]
  }
}

resource "azurerm_key_vault_secret" "secret" {
  name         = "TestSecret"
  value        = "HelloFromStandaloneLab"
  key_vault_id = azurerm_key_vault.kv.id
}

# Private Endpoint
resource "azurerm_private_endpoint" "pe" {
  name                = "pe-kv-dns-lab"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "psc-kv-dns-lab"
    private_connection_resource_id = azurerm_key_vault.kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
}

# Private DNS Zone
resource "azurerm_private_dns_zone" "dns" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  # Lab 2: Missing VNet Link
  # If scenario is 'dns_exercise2', we skip creating this link (count = 0)
  count                 = var.lab_scenario == "dns_exercise2" ? 0 : 1
  
  name                  = "link-vnet-dns-lab"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

# DNS A Record - The "Breakable" Part
resource "azurerm_private_dns_a_record" "kv_record" {
  name                = azurerm_key_vault.kv.name
  zone_name           = azurerm_private_dns_zone.dns.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  
  # DNS LAB 1: Connectivity Failure
  # Logic: If scenario is 'dns_exercise1', use fake IP. Otherwise use real IP.
  records = [
    var.lab_scenario == "dns_exercise1" ? "10.1.2.50" : azurerm_private_endpoint.pe.private_service_connection[0].private_ip_address
  ]
}

# VM (Agent)
resource "azurerm_public_ip" "pip" {
  name                = "pip-agent-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-agent-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-agent-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-agent-dns-lab"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s"
  admin_username      = var.admin_username
  
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_key
  }

  disable_password_authentication = true
  
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    admin_username = var.admin_username
    ado_org_url    = var.ado_org_url
    ado_pat        = var.ado_pat
    ado_pool_name  = var.ado_pool_name
  }))
}
