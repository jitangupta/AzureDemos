output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "aks_system_subnet_id" {
  description = "ID of the AKS system subnet"
  value       = azurerm_subnet.aks_system.id
}

output "aks_user_subnet_id" {
  description = "ID of the AKS user subnet"
  value       = azurerm_subnet.aks_user.id
}

output "private_endpoints_subnet_id" {
  description = "ID of the private endpoints subnet"
  value       = azurerm_subnet.private_endpoints.id
}

output "application_gateway_subnet_id" {
  description = "ID of the application gateway subnet"
  value       = azurerm_subnet.application_gateway.id
}

output "application_gateway_id" {
  description = "ID of the application gateway"
  value       = azurerm_application_gateway.main.id
}

output "application_gateway_public_ip" {
  description = "Public IP address of the application gateway"
  value       = azurerm_public_ip.application_gateway.ip_address
}

output "postgres_private_dns_zone_id" {
  description = "ID of the PostgreSQL private DNS zone"
  value       = azurerm_private_dns_zone.postgres.id
}

output "postgres_private_dns_zone_name" {
  description = "Name of the PostgreSQL private DNS zone"
  value       = azurerm_private_dns_zone.postgres.name
}

output "storage_private_dns_zone_id" {
  description = "ID of the storage private DNS zone"
  value       = azurerm_private_dns_zone.storage.id
}

output "storage_private_dns_zone_name" {
  description = "Name of the storage private DNS zone"
  value       = azurerm_private_dns_zone.storage.name
}

output "key_vault_private_dns_zone_id" {
  description = "ID of the Key Vault private DNS zone"
  value       = azurerm_private_dns_zone.key_vault.id
}

output "container_registry_private_dns_zone_id" {
  description = "ID of the Container Registry private DNS zone"
  value       = azurerm_private_dns_zone.container_registry.id
}