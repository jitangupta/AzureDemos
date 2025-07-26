# Enterprise Chatwoot on Azure AKS - Terraform Infrastructure

This Terraform configuration deploys a production-ready, SOC2-compliant Chatwoot infrastructure on Azure Kubernetes Service (AKS).

## Architecture Overview

- **Target Scale**: 100 agents, 1,500-3,000 daily queries
- **RTO/RPO**: 4 hours
- **Budget**: ~$1,065/month enterprise-ready
- **Compliance**: SOC2 patterns with full security stack

## Prerequisites

1. **Azure CLI** installed and authenticated
2. **Terraform** >= 1.0 installed
3. **kubectl** installed for Kubernetes management
4. **Appropriate Azure permissions** for resource creation

## Quick Start

1. **Clone and prepare configuration:**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

2. **Initialize and deploy:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Connect to AKS cluster:**
   ```bash
   az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw aks_cluster_name)
   ```

## Critical Gotchas Addressed

### ✅ AGIC Permissions and Dependencies
- Application Gateway Ingress Controller properly configured with Contributor role
- Network Contributor role on Application Gateway subnet
- Reader role on resource group
- Proper dependency ordering to prevent race conditions

### ✅ Private DNS Zone Linking to AKS VNet
- All private DNS zones linked to AKS VNet for proper resolution
- PostgreSQL: `privatelink.postgres.database.azure.com`
- Storage: `privatelink.blob.core.windows.net`
- Key Vault: `privatelink.vaultcore.azure.net`
- Container Registry: `privatelink.azurecr.io`

### ✅ ACR Authentication Role Assignments
- AcrPull role assigned to AKS kubelet identity
- Prevents image pull failures from private registry

### ✅ Storage Account for Chatwoot File Uploads
- Dedicated storage account with blob containers
- Private endpoint for secure access
- Proper configuration for Active Storage service

### ✅ Certificate Pre-provisioning
- SSL certificate created in Key Vault before Application Gateway
- Self-signed for demo (replace with Let's Encrypt for production)

### ✅ Proper Resource Ordering
- All dependencies managed with `depends_on` clauses
- Private DNS zones created before private endpoints
- RBAC assignments after resource creation

## Module Structure

```
terraform/
├── main.tf                 # Root configuration
├── variables.tf            # Input variables
├── outputs.tf             # Output values
├── versions.tf            # Provider versions
├── terraform.tfvars.example
└── modules/
    ├── networking/        # VNet, subnets, NSGs, private DNS
    ├── security/         # Key Vault, ACR, private endpoints
    ├── data/             # PostgreSQL, Redis, storage accounts
    ├── aks/              # AKS cluster and node pools
    └── monitoring/       # Log Analytics, Application Insights
```

## Cost Breakdown (~$1,065/month)

### Core Infrastructure ($495)
- **AKS Cluster**: $320 (B2s system + D2s_v3 user nodes)
- **PostgreSQL Flexible Server**: $75 (B1ms SKU)
- **Redis Standard**: $75 (C1 capacity)
- **Storage Account**: $25 (Standard LRS)

### Enterprise Security Stack ($440)
- **Application Gateway WAF_v2**: $245
- **Private Endpoints (×4)**: $60
- **Key Vault Premium**: $20
- **Private DNS Zones (×4)**: $15
- **Log Analytics (365-day retention)**: $100

### Operational Overhead ($130)
- **Backup storage (geo-redundant)**: $35
- **Egress bandwidth**: $75
- **Container Registry Premium**: $20

## SOC2 Compliance Features

- ✅ All data services use private endpoints
- ✅ Network security groups on all subnets
- ✅ Audit logging enabled (365-day retention)
- ✅ Key Vault RBAC authorization
- ✅ Container image scanning enabled
- ✅ Backup retention policies configured
- ✅ Private cluster with no public access
- ✅ Encryption at rest and in transit

## Post-Deployment Steps

1. **Create Chatwoot namespace:**
   ```bash
   kubectl create namespace chatwoot
   ```

2. **Create database secrets:**
   ```bash
   kubectl create secret generic chatwoot-secrets -n chatwoot \
     --from-literal=postgres-url="postgresql://$(terraform output -raw postgres_username):$(terraform output -raw postgres_password)@$(terraform output -raw postgres_fqdn):5432/$(terraform output -raw postgres_database_name)" \
     --from-literal=redis-url="redis://:$(terraform output -raw redis_primary_access_key)@$(terraform output -raw redis_hostname):6380" \
     --from-literal=storage-account-name="$(terraform output -raw storage_account_name)" \
     --from-literal=storage-access-key="$(terraform output -raw storage_account_primary_access_key)"
   ```

3. **Deploy Chatwoot application:**
   - Use the provided Kubernetes manifests
   - Configure Application Gateway Ingress
   - Set up SSL certificate from Key Vault

4. **Configure DNS:**
   Point your domain to the Application Gateway public IP:
   ```bash
   terraform output application_gateway_public_ip
   ```

## Security Best Practices

- **Private cluster**: No public API server access
- **Private endpoints**: All data services isolated
- **RBAC**: Least privilege access control
- **Network policies**: Azure CNI with network policies
- **Image scanning**: Enabled on Container Registry
- **Audit logging**: All operations logged and retained
- **Encryption**: TLS 1.2+ enforced everywhere

## Disaster Recovery

- **PostgreSQL**: Geo-redundant backups (35-day retention)
- **Storage**: GRS replication for backup storage
- **Redis**: RDB snapshots every 60 minutes
- **Logs**: GRS storage with 7-year retention

## Monitoring and Alerting

- **Log Analytics**: Centralized logging and queries
- **Application Insights**: APM and performance monitoring
- **Metric Alerts**: CPU, memory, and availability monitoring
- **Action Groups**: Email and webhook notifications

## Troubleshooting Common Issues

### Certificate Issues
- Ensure Key Vault certificate is created before Application Gateway
- Check RBAC permissions for certificate access

### DNS Resolution Failures
- Verify private DNS zones are linked to AKS VNet
- Check private endpoint configuration

### Image Pull Failures
- Confirm AcrPull role assignment to kubelet identity
- Verify Container Registry private endpoint

### AGIC Configuration Issues
- Check Application Gateway backend pool configuration
- Verify AGIC identity has proper permissions

## Support and Maintenance

- **Updates**: Regular Terraform and provider updates
- **Scaling**: Adjust node counts in terraform.tfvars
- **Monitoring**: Review Log Analytics queries regularly
- **Backup Testing**: Monthly restore testing recommended

For issues or questions, refer to the troubleshooting section or Azure documentation.