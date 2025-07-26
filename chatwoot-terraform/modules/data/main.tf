# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                = "psql-${var.application_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # Configuration for 100 agents workload
  sku_name                     = var.postgres_sku
  storage_mb                   = var.postgres_storage_mb
  version                      = "15"
  
  # SOC2 compliance features
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = true
  
  # Private access only - delegated subnet approach
  delegated_subnet_id = var.private_endpoints_subnet_id
  private_dns_zone_id = var.postgres_private_dns_zone_id

  # Security configurations
  zone                      = "1"
  high_availability {
    mode = "ZoneRedundant"
  }

  # Authentication
  administrator_login    = "chatwoot"
  administrator_password = random_password.postgres_password.result

  # Enable automatic failover
  create_mode = "Default"

  depends_on = [
    data.azurerm_private_dns_zone.postgres
  ]
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "chatwoot" {
  name      = "chatwoot_production"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# PostgreSQL Configuration for performance
resource "azurerm_postgresql_flexible_server_configuration" "shared_preload_libraries" {
  name      = "shared_preload_libraries"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "pg_stat_statements"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_statement" {
  name      = "log_statement"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "all"
}

# Generate PostgreSQL password
resource "random_password" "postgres_password" {
  length  = 16
  special = true
}

# Reference to PostgreSQL private DNS zone
data "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.network_resource_group_name
}

# Azure Cache for Redis
resource "azurerm_redis_cache" "main" {
  name                = "redis-${var.application_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  capacity            = var.redis_capacity
  family              = var.redis_family
  sku_name            = var.redis_sku_name
  tags                = var.tags

  # SOC2 compliance features
  non_ssl_port_enabled         = false
  minimum_tls_version          = "1.2"
  public_network_access_enabled = false

  # Enable persistence for enterprise
  redis_configuration {
    rdb_backup_enabled            = true
    rdb_backup_frequency          = 60
    rdb_backup_max_snapshot_count = 1
    notify_keyspace_events        = "Ex"
  }

  # Private endpoint will be created separately
  subnet_id = var.private_endpoints_subnet_id
}

# Redis Private Endpoint
resource "azurerm_private_endpoint" "redis" {
  name                = "pe-redis-${var.application_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-redis"
    private_connection_resource_id = azurerm_redis_cache.main.id
    subresource_names             = ["redisCache"]
    is_manual_connection          = false
  }

  depends_on = [azurerm_redis_cache.main]
}

# Storage Account for Chatwoot file uploads (CRITICAL requirement)
resource "azurerm_storage_account" "chatwoot" {
  name                     = "st${var.application_name}${replace(var.resource_suffix, "-", "")}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags

  # SOC2 compliance features
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning for audit trail
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  # Private endpoint only access
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# Storage Container for Chatwoot uploads
resource "azurerm_storage_container" "uploads" {
  name                  = "uploads"
  storage_account_name  = azurerm_storage_account.chatwoot.name
  container_access_type = "private"
}

# Storage Container for Chatwoot avatars
resource "azurerm_storage_container" "avatars" {
  name                  = "avatars"
  storage_account_name  = azurerm_storage_account.chatwoot.name
  container_access_type = "private"
}

# Storage Private Endpoint
resource "azurerm_private_endpoint" "storage" {
  name                = "pe-storage-${var.application_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-storage"
    private_connection_resource_id = azurerm_storage_account.chatwoot.id
    subresource_names             = ["blob"]
    is_manual_connection          = false
  }

  private_dns_zone_group {
    name                 = "storage-dns-zone-group"
    private_dns_zone_ids = [var.storage_private_dns_zone_id]
  }

  depends_on = [azurerm_storage_account.chatwoot]
}

# Backup Storage Account for disaster recovery
resource "azurerm_storage_account" "backup" {
  name                     = "stbak${var.application_name}${replace(var.resource_suffix, "-", "")}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  tags                     = merge(var.tags, { Purpose = "Backup" })

  # SOC2 compliance features
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 90
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# Backup Storage Container
resource "azurerm_storage_container" "database_backup" {
  name                  = "database-backups"
  storage_account_name  = azurerm_storage_account.backup.name
  container_access_type = "private"
}