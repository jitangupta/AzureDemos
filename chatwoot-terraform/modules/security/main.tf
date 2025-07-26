data "azurerm_client_config" "current" {}

# Azure Key Vault
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.application_name}-${substr(var.resource_suffix, 0, 12)}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "premium"
  tags                = var.tags

  # Enable RBAC instead of access policies for SOC2 compliance
  enable_rbac_authorization = true
  
  # SOC2 compliance features
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  # Private access only
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

# Key Vault Private Endpoint
resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-kv-${var.application_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-key-vault"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names             = ["vault"]
    is_manual_connection          = false
  }

  private_dns_zone_group {
    name                 = "key-vault-dns-zone-group"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.key_vault.id]
  }

  depends_on = [azurerm_key_vault.main]
}

# Reference to Key Vault private DNS zone
data "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.network_resource_group_name
}

# Pre-create SSL certificate for demo purposes
resource "azurerm_key_vault_certificate" "ssl_cert" {
  name         = var.ssl_certificate_name
  key_vault_id = azurerm_key_vault.main.id
  tags         = var.tags

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject            = "CN=${var.domain_name}"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = [var.domain_name, "www.${var.domain_name}"]
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.current_user_kv_admin,
    azurerm_private_endpoint.key_vault
  ]
}

# RBAC for Key Vault - Current user needs admin access to create certificates
resource "azurerm_role_assignment" "current_user_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# RBAC for Key Vault - Admin group access (if provided)
resource "azurerm_role_assignment" "admin_group_kv_admin" {
  count                = var.admin_group_object_id != "" ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.admin_group_object_id
}

# Container Registry
resource "azurerm_container_registry" "main" {
  name                = "acr${var.application_name}${replace(var.resource_suffix, "-", "")}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Premium"
  admin_enabled       = false
  tags                = var.tags

  # SOC2 compliance features
  public_network_access_enabled = false
  
  # Enable image scanning and trust policy
  trust_policy {
    enabled = true
  }

  retention_policy {
    enabled = true
    days    = 30
  }

}

# Container Registry Private Endpoint
resource "azurerm_private_endpoint" "container_registry" {
  name                = "pe-acr-${var.application_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-container-registry"
    private_connection_resource_id = azurerm_container_registry.main.id
    subresource_names             = ["registry"]
    is_manual_connection          = false
  }

  private_dns_zone_group {
    name                 = "acr-dns-zone-group"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.container_registry.id]
  }

  depends_on = [azurerm_container_registry.main]
}

# Reference to Container Registry private DNS zone
data "azurerm_private_dns_zone" "container_registry" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.network_resource_group_name
}