variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "application_name" {
  description = "Application name"
  type        = string
}

variable "resource_suffix" {
  description = "Resource suffix for unique naming"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
}

variable "system_node_vm_size" {
  description = "VM size for system node pool"
  type        = string
}

variable "user_node_vm_size" {
  description = "VM size for user node pool"
  type        = string
}

variable "node_count_min" {
  description = "Minimum number of nodes in user pool"
  type        = number
}

variable "node_count_max" {
  description = "Maximum number of nodes in user pool"
  type        = number
}

variable "system_subnet_id" {
  description = "ID of the AKS system subnet"
  type        = string
}

variable "user_subnet_id" {
  description = "ID of the AKS user subnet"
  type        = string
}

variable "application_gateway_id" {
  description = "ID of the Application Gateway"
  type        = string
}

variable "virtual_network_name" {
  description = "Name of the virtual network"
  type        = string
}

variable "network_resource_group_name" {
  description = "Name of the network resource group"
  type        = string
}

variable "container_registry_id" {
  description = "ID of the Container Registry"
  type        = string
}

variable "key_vault_id" {
  description = "ID of the Key Vault"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}