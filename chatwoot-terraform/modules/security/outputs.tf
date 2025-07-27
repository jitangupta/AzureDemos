output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "container_registry_id" {
  description = "ID of the Container Registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_name" {
  description = "Name of the Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Container Registry"
  value       = azurerm_container_registry.main.login_server
}

/*
output "ssl_certificate_secret_id" {
  description = "Secret ID of the SSL certificate"
  value       = azurerm_key_vault_certificate.ssl_cert.secret_id
}

output "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  value       = azurerm_key_vault_certificate.ssl_cert.name
}
*/