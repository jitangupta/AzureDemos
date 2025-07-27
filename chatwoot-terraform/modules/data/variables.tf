variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "network_resource_group_name" {
  description = "Name of the network resource group"
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

variable "postgres_sku" {
  description = "PostgreSQL Flexible Server SKU"
  type        = string
}

variable "postgres_storage_mb" {
  description = "PostgreSQL storage in MB"
  type        = number
}

variable "backup_retention_days" {
  description = "Database backup retention in days"
  type        = number
}

variable "redis_capacity" {
  description = "Redis cache capacity"
  type        = number
}

variable "redis_family" {
  description = "Redis cache family"
  type        = string
}

variable "redis_sku_name" {
  description = "Redis cache SKU"
  type        = string
}

variable "virtual_network_id" {
  description = "ID of the virtual network"
  type        = string
}

variable "private_endpoints_subnet_id" {
  description = "ID of the private endpoints subnet"
  type        = string
}

variable "postgres_subnet_id" {
  description = "ID of the PostgreSQL subnet"
  type        = string
}

variable "postgres_private_dns_zone_id" {
  description = "ID of the PostgreSQL private DNS zone"
  type        = string
}

variable "storage_private_dns_zone_id" {
  description = "ID of the storage private DNS zone"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}