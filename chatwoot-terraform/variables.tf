variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region for primary resources"
  type        = string
  default     = "East US"
}

variable "dr_location" {
  description = "Azure region for disaster recovery"
  type        = string
  default     = "West US 2"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.29"
}

variable "node_count_min" {
  description = "Minimum number of nodes in user pool"
  type        = number
  default     = 2
}

variable "node_count_max" {
  description = "Maximum number of nodes in user pool"
  type        = number
  default     = 4
}

variable "system_node_vm_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_B2s"
}

variable "user_node_vm_size" {
  description = "VM size for user node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "postgres_sku" {
  description = "PostgreSQL Flexible Server SKU"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "PostgreSQL storage in MB"
  type        = number
  default     = 32768
}

variable "redis_capacity" {
  description = "Redis cache capacity"
  type        = number
  default     = 1
}

variable "redis_family" {
  description = "Redis cache family"
  type        = string
  default     = "C"
}

variable "redis_sku_name" {
  description = "Redis cache SKU"
  type        = string
  default     = "Standard"
}

variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = "IT"
}

variable "application_name" {
  description = "Application name for resource naming"
  type        = string
  default     = "chatwoot"
}

variable "admin_group_object_id" {
  description = "Azure AD group object ID for admin access"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Log Analytics workspace retention in days (SOC2 requirement)"
  type        = number
  default     = 365
}

variable "backup_retention_days" {
  description = "Database backup retention in days"
  type        = number
  default     = 35
}

variable "ssl_certificate_name" {
  description = "Name for SSL certificate in Key Vault"
  type        = string
  default     = "chatwoot-ssl-cert"
}

variable "domain_name" {
  description = "Domain name for SSL certificate"
  type        = string
  default     = "chatwoot.example.com"
}