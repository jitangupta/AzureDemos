data "azurerm_client_config" "current" {}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.application_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-${var.application_name}-${var.environment}"
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  # Private cluster for SOC2 compliance
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false

  # System node pool (tainted for system workloads only)
  default_node_pool {
    name                        = "system"
    vm_size                     = var.system_node_vm_size
    node_count                  = 2
    vnet_subnet_id              = var.system_subnet_id
    only_critical_addons_enabled = true
    
    # Enable auto-scaling for system pool
    enable_auto_scaling = true
    min_count          = 1
    max_count          = 3

    # OS and security settings
    os_disk_size_gb = 100
    os_disk_type    = "Managed"
    max_pods        = 30

    # Node labels for system workloads
    node_labels = {
      "node.kubernetes.io/pool-type" = "system"
    }

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Managed identity for AKS
  identity {
    type = "SystemAssigned"
  }

  # Network configuration
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  # CRITICAL: Enable Application Gateway Ingress Controller
  ingress_application_gateway {
    gateway_id = var.application_gateway_id
  }

  # Azure RBAC for Kubernetes authorization
  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  # SOC2 compliance features
  role_based_access_control_enabled = true
  
  # API server access profile for private cluster
  api_server_access_profile {
    authorized_ip_ranges = []
  }

  # Enable monitoring
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  # Enable Key Vault Secrets Provider
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # Auto-scaler profile
  auto_scaler_profile {
    balance_similar_node_groups      = false
    expander                        = "random"
    max_graceful_termination_sec    = "600"
    max_node_provisioning_time      = "15m"
    max_unready_nodes              = 3
    max_unready_percentage         = 45
    new_pod_scale_up_delay         = "10s"
    scale_down_delay_after_add     = "10m"
    scale_down_delay_after_delete  = "10s"
    scale_down_delay_after_failure = "3m"
    scan_interval                  = "10s"
    scale_down_unneeded            = "10m"
    scale_down_unready             = "20m"
    scale_down_utilization_threshold = 0.5
  }

}

# User node pool for application workloads
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_vm_size
  enable_auto_scaling   = true
  min_count            = var.node_count_min
  max_count            = var.node_count_max
  vnet_subnet_id       = var.user_subnet_id
  tags                 = var.tags

  # OS and security settings
  os_disk_size_gb = 100
  os_disk_type    = "Managed"
  max_pods        = 50

  # Node labels for application workloads
  node_labels = {
    "node.kubernetes.io/pool-type" = "user"
    "workload"                     = "application"
  }

  # Node taints to ensure only application workloads run here
  node_taints = [
    "workload=application:NoSchedule"
  ]

  upgrade_settings {
    max_surge = "33%"
  }
}

# CRITICAL: ACR Pull Role Assignment for AKS
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  
  # Prevent race condition
  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}

# CRITICAL: Application Gateway Contributor role for AGIC
resource "azurerm_role_assignment" "agic_contributor" {
  scope                = var.application_gateway_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}

# Network Contributor role for AGIC on Application Gateway subnet
data "azurerm_subnet" "application_gateway" {
  name                 = "snet-application-gateway"
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.network_resource_group_name
}

resource "azurerm_role_assignment" "agic_network_contributor" {
  scope                = data.azurerm_subnet.application_gateway.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}

# Reader role for AGIC on resource group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

resource "azurerm_role_assignment" "agic_reader" {
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}

# Key Vault Secrets User role for AKS to access secrets
resource "azurerm_role_assignment" "aks_key_vault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].object_id

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}

# Diagnostic settings for AKS cluster
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name               = "aks-diagnostics"
  target_resource_id = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  enabled_log {
    category = "guard"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}