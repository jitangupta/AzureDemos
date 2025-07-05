# SplendidCRM – Lift & Shift on Azure IaaS

## 📝 Project Summary

This project simulates a real-world Lift & Shift migration of a legacy .NET Framework 4.x application—[SplendidCRM Community Edition](https://github.com/SplendidCRM/SplendidCRM-Community)—to Azure using **IaaS components**.

SplendidCRM is a CRM solution built with ASP.NET Web Forms and SQL Server, making it an ideal candidate for Lift & Shift scenarios.

---

## 🎯 Phase 1 Goal

Provision the entire infrastructure using **ARM templates + PowerShell scripts**, deploy the SplendidCRM application on a Windows VM (IIS), configure SQL Server on a separate VM, and route public traffic securely through an Azure Application Gateway with SSL termination.

---

## ✅ Success Criteria

- 🔧 **Provisioned Azure infrastructure** using ARM templates:
  - Resource Group
  - Virtual Network with subnet segmentation (`web`, `db`, `agw`)
  - NSGs (restrictive by default)
  - Windows VM for Web + IIS
  - Windows VM for SQL Server
  - Application Gateway (SSL terminated)
  - Public IP and DNS for access

- 🧱 **Bootstrapped VMs** using custom scripts:
  - IIS installed with .NET Framework 4.x support
  - SQL Server Developer Edition installed and configured
  - CRM files deployed on IIS
  - SQL schema and seed data loaded

- 🔐 **Security Configured**:
  - JIT VM access enabled for RDP
  - NSG rules scoped to subnets/IPs only
  - Encrypted credentials/connection strings
  - Backup and logs stored inside respective VMs

- 🌐 **Working App Access**:
  - Public access to the CRM through Application Gateway
  - Internal secure communication between web and DB subnets

- 📹 **Recorded Demo & Documentation**:
  - Architecture walkthrough
  - Deployment flow and code decisions
  - Teardown process

---

## 📂 Folder Structure (Expected)
SplendidCRM-Community/
├── templates/ # ARM templates
│ ├── network.json
│ ├── vms.json
│ └── parameters.json
├── scripts/ # PowerShell setup scripts
│ ├── install-iis.ps1
│ ├── deploy-app.ps1
│ └── setup-sql.ps1
├── backups/ # Optional backup scripts
├── docs/
│ └── architecture-diagram.png
├── README-PHASE1.md

---

## 🔧 Tools Used

- Azure Resource Manager (ARM)
- PowerShell (VM bootstrapping)
- IIS for .NET hosting
- SQL Server Developer Edition
- Azure Application Gateway (SSL)