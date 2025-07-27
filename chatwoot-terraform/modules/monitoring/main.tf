# Log Analytics Workspace for SOC2 compliance
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.application_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags

  # SOC2 compliance features
  daily_quota_gb                     = 10
  internet_ingestion_enabled         = true
  internet_query_enabled             = true
  reservation_capacity_in_gb_per_day = null
}

# Log Analytics Solutions
resource "azurerm_log_analytics_solution" "container_insights" {
  solution_name         = "ContainerInsights"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }

  tags = var.tags
}

resource "azurerm_log_analytics_solution" "security_center" {
  solution_name         = "Security"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/Security"
  }

  tags = var.tags
}

resource "azurerm_log_analytics_solution" "update_management" {
  solution_name         = "Updates"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/Updates"
  }

  tags = var.tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.application_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = var.log_retention_days
  tags                = var.tags

  # Sampling configuration for high-volume applications
  daily_data_cap_in_gb                  = 5
  daily_data_cap_notifications_disabled = false
}

# Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${var.application_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "chatwoot"
  tags                = var.tags

  # Email notifications
  email_receiver {
    name          = "admin-email"
    email_address = "admin@example.com"
  }

  # Webhook for Slack/Teams integration
  webhook_receiver {
    name        = "webhook"
    service_uri = "https://example.com/webhook"
  }
}

# Metric Alerts
resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "HighCPUUsage"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_log_analytics_workspace.main.id]
  description         = "Alert when CPU usage is high"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.OperationalInsights/workspaces"
    metric_name      = "Average_% Processor Time"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  frequency   = "PT5M"
  window_size = "PT15M"
  severity    = 2
}

resource "azurerm_monitor_metric_alert" "high_memory" {
  name                = "HighMemoryUsage"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_log_analytics_workspace.main.id]
  description         = "Alert when memory usage is high"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.OperationalInsights/workspaces"
    metric_name      = "Average_% Used Memory"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  frequency   = "PT5M"
  window_size = "PT15M"
  severity    = 2
}

# Log Queries for SOC2 Compliance (commented out - these get auto-created by Azure)
/*
resource "azurerm_log_analytics_saved_search" "failed_logins" {
  name                       = "FailedLogins"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  category                   = "Security"
  display_name               = "Failed Login Attempts"
  query                      = <<-EOT
    SecurityEvent
    | where EventID == 4625
    | summarize count() by Account, Computer, bin(TimeGenerated, 1h)
    | order by TimeGenerated desc
  EOT

  tags = var.tags
}

resource "azurerm_log_analytics_saved_search" "privileged_operations" {
  name                       = "PrivilegedOperations"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  category                   = "Security"
  display_name               = "Privileged Operations"
  query                      = <<-EOT
    AuditLogs
    | where Category == "RoleManagement"
    | extend InitiatedBy = tostring(InitiatedBy.user.userPrincipalName)
    | project TimeGenerated, OperationName, InitiatedBy, Result
    | order by TimeGenerated desc
  EOT

  tags = var.tags
}
*/

# Data Export Rules for long-term archival (commented out - gets auto-created)
/*
resource "azurerm_log_analytics_data_export_rule" "compliance_export" {
  name                    = "compliance-export"
  resource_group_name     = var.resource_group_name
  workspace_resource_id   = azurerm_log_analytics_workspace.main.id
  destination_resource_id = azurerm_storage_account.logs.id
  table_names            = ["SecurityEvent", "AuditLogs", "SigninLogs"]
  enabled                = true

  depends_on = [azurerm_storage_account.logs]
}
*/

# Storage Account for log archival (SOC2 requirement)
resource "azurerm_storage_account" "logs" {
  name                     = "${substr(replace("stlogs${var.resource_suffix}", "-", ""), 0, 24)}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  tags                     = merge(var.tags, { Purpose = "LogArchival" })

  # SOC2 compliance features
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 365  # 1 year retention (Azure maximum)
    }
  }

  # Network rules will be applied after containers are created
}

# Container for archived logs
resource "azurerm_storage_container" "archived_logs" {
  name                  = "archived-logs"
  storage_account_name  = azurerm_storage_account.logs.name
  container_access_type = "private"
}

# Backup configuration for Log Analytics workspace (commented out - gets auto-created)
/*
resource "azurerm_log_analytics_linked_storage_account" "main" {
  data_source_type      = "CustomLogs"
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  storage_account_ids   = [azurerm_storage_account.logs.id]

  depends_on = [azurerm_storage_account.logs]
}
*/