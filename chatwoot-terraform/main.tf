data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  common_tags = {
    Environment = var.environment
    Application = var.application_name
    ManagedBy   = "Terraform"
    CostCenter  = var.cost_center
    Compliance  = "SOC2"
  }

  resource_suffix = "${var.environment}-${random_string.suffix.result}"
}

# Resource Groups
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.application_name}-${var.environment}-${replace(var.location, " ", "")}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "dr" {
  name     = "rg-${var.application_name}-dr-${replace(var.dr_location, " ", "")}"
  location = var.dr_location
  tags     = merge(local.common_tags, { Purpose = "DisasterRecovery" })
}

resource "azurerm_resource_group" "network" {
  name     = "rg-${var.application_name}-network-${replace(var.location, " ", "")}"
  location = var.location
  tags     = merge(local.common_tags, { Purpose = "Networking" })
}

# Networking Module
module "networking" {
  source = "./modules/networking"

  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  environment         = var.environment
  application_name    = var.application_name
  tags                = local.common_tags
}

# Security Module
module "security" {
  source = "./modules/security"

  resource_group_name         = azurerm_resource_group.main.name
  network_resource_group_name = azurerm_resource_group.network.name
  location                    = azurerm_resource_group.main.location
  environment                 = var.environment
  application_name            = var.application_name
  resource_suffix             = local.resource_suffix
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  admin_group_object_id       = var.admin_group_object_id
  ssl_certificate_name        = var.ssl_certificate_name
  domain_name                 = var.domain_name
  tags                        = local.common_tags

  # Network dependencies
  virtual_network_id          = module.networking.virtual_network_id
  private_endpoints_subnet_id = module.networking.private_endpoints_subnet_id

  depends_on = [module.networking]
}

# Monitoring Module
module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  application_name    = var.application_name
  resource_suffix     = local.resource_suffix
  log_retention_days  = var.log_retention_days
  tags                = local.common_tags
}

# Data Services Module
module "data" {
  source = "./modules/data"

  resource_group_name         = azurerm_resource_group.main.name
  network_resource_group_name = azurerm_resource_group.network.name
  location                    = azurerm_resource_group.main.location
  environment                 = var.environment
  application_name            = var.application_name
  resource_suffix             = local.resource_suffix
  tags                        = local.common_tags

  # Database configuration
  postgres_sku          = var.postgres_sku
  postgres_storage_mb   = var.postgres_storage_mb
  backup_retention_days = var.backup_retention_days

  # Redis configuration
  redis_capacity = var.redis_capacity
  redis_family   = var.redis_family
  redis_sku_name = var.redis_sku_name

  # Network dependencies
  virtual_network_id           = module.networking.virtual_network_id
  private_endpoints_subnet_id  = module.networking.private_endpoints_subnet_id
  postgres_private_dns_zone_id = module.networking.postgres_private_dns_zone_id
  storage_private_dns_zone_id  = module.networking.storage_private_dns_zone_id

  depends_on = [module.networking]
}

# AKS Module
module "aks" {
  source = "./modules/aks"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  application_name    = var.application_name
  resource_suffix     = local.resource_suffix
  tags                = local.common_tags

  # AKS configuration
  kubernetes_version  = var.kubernetes_version
  system_node_vm_size = var.system_node_vm_size
  user_node_vm_size   = var.user_node_vm_size
  node_count_min      = var.node_count_min
  node_count_max      = var.node_count_max

  # Network dependencies
  system_subnet_id       = module.networking.aks_system_subnet_id
  user_subnet_id         = module.networking.aks_user_subnet_id
  application_gateway_id = module.networking.application_gateway_id

  # Security dependencies
  container_registry_id = module.security.container_registry_id
  key_vault_id          = module.security.key_vault_id

  # Monitoring dependencies
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  depends_on = [
    module.networking,
    module.security,
    module.monitoring
  ]
}