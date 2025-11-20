variable "location" {
  description = "Azure Region"
  default     = "westus2"
}

variable "resource_group_name" {
  description = "Name of the Resource Group"
  default     = "rg-dns-lab"
}

variable "vnet_name" {
  description = "Name of the VNet"
  default     = "vnet-dns-lab"
}

variable "subnet_name" {
  description = "Name of the Subnet"
  default     = "snet-agents"
}

variable "ado_org_url" {
  description = "Azure DevOps Organization URL (e.g. https://dev.azure.com/myorg)"
  type        = string
}

variable "ado_pat" {
  description = "Personal Access Token with Agent Pools (Manage) scope"
  type        = string
  sensitive   = true
}

variable "ado_pool_name" {
  description = "Name of the Agent Pool to register with"
  default     = "Default"
}

variable "admin_username" {
  default = "azureuser"
}

variable "admin_password" {
  description = "Password for the VM"
  default     = "P@ssw0rd1234!"
  sensitive   = true
}

variable "lab_scenario" {
  description = "Controls the lab state: 'base' (working) or 'dns_exercise1' (broken)"
  default     = "base"
}

variable "sp_object_id" {
  description = "Object ID of the Service Principal for the Service Connection"
  type        = string
}
