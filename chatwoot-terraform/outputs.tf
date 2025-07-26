output "resource_group_name" {
  description = "Name of the main resource group"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = module.aks.cluster_fqdn
}

output "aks_cluster_identity" {
  description = "AKS cluster managed identity"
  value       = module.aks.cluster_identity
  sensitive   = true
}

output "container_registry_login_server" {
  description = "Login server URL for the container registry"
  value       = module.security.container_registry_login_server
}

output "container_registry_name" {
  description = "Name of the container registry"
  value       = module.security.container_registry_name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.security.key_vault_uri
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.security.key_vault_name
}

output "postgres_fqdn" {
  description = "FQDN of the PostgreSQL server"
  value       = module.data.postgres_fqdn
  sensitive   = true
}

output "postgres_database_name" {
  description = "Name of the PostgreSQL database"
  value       = module.data.postgres_database_name
}

output "redis_hostname" {
  description = "Hostname of the Redis cache"
  value       = module.data.redis_hostname
  sensitive   = true
}

output "redis_port" {
  description = "Port of the Redis cache"
  value       = module.data.redis_port
}

output "storage_account_name" {
  description = "Name of the storage account for Chatwoot file uploads"
  value       = module.data.storage_account_name
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = module.data.storage_account_primary_blob_endpoint
}

output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = module.networking.application_gateway_public_ip
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = module.monitoring.log_analytics_workspace_id
}

output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = module.networking.virtual_network_name
}

output "private_dns_zones" {
  description = "Private DNS zones created"
  value = {
    postgres = module.networking.postgres_private_dns_zone_name
    storage  = module.networking.storage_private_dns_zone_name
  }
}

output "deployment_instructions" {
  description = "Next steps for deployment"
  value       = <<-EOT
    
    Deployment completed successfully! Next steps:
    
    1. Connect to AKS cluster:
       az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name}
    
    2. Create Chatwoot namespace:
       kubectl create namespace chatwoot
    
    3. Create secrets for database connections:
       kubectl create secret generic chatwoot-secrets -n chatwoot \
         --from-literal=postgres-url="postgresql://chatwoot@${module.data.postgres_fqdn}:5432/${module.data.postgres_database_name}" \
         --from-literal=redis-url="redis://${module.data.redis_hostname}:${module.data.redis_port}" \
         --from-literal=storage-account-name="${module.data.storage_account_name}"
    
    4. Deploy Chatwoot application using the provided Kubernetes manifests
    
    5. Configure DNS to point ${var.domain_name} to ${module.networking.application_gateway_public_ip}
    
    Resources created:
    - AKS Cluster: ${module.aks.cluster_name}
    - Container Registry: ${module.security.container_registry_name}
    - PostgreSQL: ${module.data.postgres_fqdn}
    - Redis: ${module.data.redis_hostname}
    - Storage Account: ${module.data.storage_account_name}
    - Key Vault: ${module.security.key_vault_name}
    
    Estimated monthly cost: ~$1,065 USD
    
  EOT
}