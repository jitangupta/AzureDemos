# SplendidCRM Deployment Guide (Azure IaaS)

This guide provides step-by-step instructions to deploy the SplendidCRM application to Azure using the provided ARM templates and PowerShell scripts.

##  Prerequisites

1.  **Azure CLI:** You must have the Azure CLI installed and configured. You can log in using `az login`.
2.  **Resource Group:** Create a resource group in your desired Azure region. All resources will be deployed into this group.

    ```bash
    az group create --name YourResourceGroupName --location "East US"
    ```

## Deployment Steps

The deployment is a two-step process. First, you provision the core network infrastructure, and then you deploy the virtual machine and the application itself.

### Step 1: Deploy the Virtual Network

This step provisions the virtual network (VNet), a subnet for the web application, and a Network Security Group (NSG) to control traffic.

-   **File to run:** `templates/network.json`
-   **What it does:**
    -   Creates a VNet (`SplendidCRM-vnet`) with an address space of `10.0.0.0/16`.
    -   Creates a subnet named `webapp` with an address range of `10.0.0.0/24`.
    -   Creates a Network Security Group (`SplendidCRM-nsg`) with the following rules:
        -   Allows inbound HTTP traffic on port 80.
        -   Allows inbound HTTPS traffic on port 443.
        -   Allows inbound RDP traffic on port 3389, but only from the IP address you specify during deployment.
    -   Associates the NSG with the `webapp` subnet.

**Command:**

```bash
az deployment group create \
    --resource-group YourResourceGroupName \
    --template-file templates/network.json \
    --parameters adminIpAddress=<Your.Public.IP.Address>
```

### Step 2: Deploy the Virtual Machine and Application

This step provisions the Windows Server VM and automatically triggers the installation and configuration scripts after the VM is created.

-   **File to run:** `templates/vm.json`
-   **What it does:**
    -   Provisions a `Standard_D2s_v3` Windows Server 2019 VM.
    -   Creates a public IP address and a network interface for the VM.
    -   Attaches the VM to the `webapp` subnet created in the previous step.
    -   Enables Just-In-Time (JIT) access for RDP on port 3389 for enhanced security.
    -   **Crucially, this template will also execute the PowerShell scripts in order.**

**Command:**

First, you need to get the ID of the subnet created in Step 1.

```bash
# Get the subnet ID
webappSubnetId=$(az network vnet subnet show --resource-group YourResourceGroupName --vnet-name SplendidCRM-vnet --name webapp --query id -o tsv)

# Deploy the VM
az deployment group create \
    --resource-group YourResourceGroupName \
    --template-file templates/vm.json \
    --parameters webappSubnetId=$webappSubnetId adminUsername=<YourAdminUsername> adminPassword=<YourSecurePassword>
```

## Automated Post-Deployment Scripts

Once the `vm.json` template is deployed, the following scripts will run automatically on the newly created virtual machine. You do not need to run them manually.

1.  **`scripts/install-iis-sql.ps1`**
    -   **Purpose:** Sets up the server environment.
    -   **Actions:**
        -   Installs Internet Information Services (IIS).
        -   Installs ASP.NET 4.8 and required IIS features.
        -   Downloads and silently installs SQL Server 2019 Developer Edition.

2.  **`scripts/deploy-app.ps1`**
    -   **Purpose:** Deploys the SplendidCRM application files.
    -   **Actions:**
        -   Downloads the latest version of SplendidCRM Community Edition from GitHub.
        -   Extracts the application files.
        -   Clears the default IIS `wwwroot` directory.
        -   Copies the SplendidCRM files to `C:\inetpub\wwwroot`.
        -   Configures the IIS application pool to use .NET CLR Version `v4.0`.

3.  **`scripts/load-db.ps1`**
    -   **Purpose:** Creates and populates the application database.
    -   **Actions:**
        -   Creates a new database named `SplendidCRM`.
        -   Executes the `SplendidCRM.sql` script to create the database schema.
        -   Executes the `vwSplendidCRM_Data.sql` script to populate the database with initial data.

## Verification

After the deployment is complete (this may take 15-20 minutes), you can find the public IP address of your new VM in the Azure portal. Open a web browser and navigate to `http://<Your-VM-Public-IP>` to access the SplendidCRM login page.

## Teardown

To delete all the resources created in this guide and avoid ongoing charges, simply delete the resource group.

```bash
az group delete --name YourResourceGroupName --yes --no-wait
```
