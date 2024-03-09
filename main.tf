locals {
  name = "abi"
  tags = {
    Application = "abi"
    Environment = "dev"
    Author      = "Mahmoud Ayman (mahmoudk1000)"
  }
}

resource "azurerm_resource_group" "main" {
  location = "West Europe"
  name     = local.name
}

module "vnet" {
  source  = "Azure/vnet/azurerm"
  version = "4.1.0"

  vnet_name           = "${local.name}-vnet"
  vnet_location       = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  use_for_each = true

  address_space       = [ "10.0.0.0/16" ]
  subnet_prefixes     = [ "10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24" ]

  tags = local.tags
}

resource "azurerm_subnet" "private-subnet" {
  name                  = "${local.name}-subnet_private"

  virtual_network_name  = module.vnet.vnet_name
  resource_group_name   = azurerm_resource_group.main.name
  
  address_prefixes = [ module.vnet.vnet_subnets[0] ]
}

resource "azurerm_public_ip" "public_ip" {
  name                 = "${local.name}-pip"

  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  
  allocation_method       = "Static"
  idle_timeout_in_minutes = 30

  tags = local.tags
}

resource "azurerm_lb" "lb" {
  name                = "LoadBalancer"

  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_lb_backend_address_pool" "public_ip_pool" {
  name            = "BackEndAddressPool"
  loadbalancer_id = azurerm_lb.lb.id
}

resource "azurerm_lb_rule" "frontend_rule" {
  loadbalancer_id                 = azurerm_lb.lb.id
  name                            = "frontendRule"
  protocol                        = "Tcp"
  frontend_port                   = 3001
  backend_port                    = 3001
  frontend_ip_configuration_name  = azurerm_lb.lb.frontend_ip_configuration[0].name
  backend_address_pool_ids        = [ azurerm_lb_backend_address_pool.public_ip_pool.id ]
}

resource "azurerm_lb_rule" "backend_rule" {
  loadbalancer_id                 = azurerm_lb.lb.id
  name                            = "backendRule"
  protocol                        = "Tcp"
  frontend_port                   = 8000
  backend_port                    = 8000
  frontend_ip_configuration_name  = azurerm_lb.lb.frontend_ip_configuration[0].name
  backend_address_pool_ids        = [ azurerm_lb_backend_address_pool.public_ip_pool.id ]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${local.name}-nsg"

  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg-link" {
  subnet_id                 = azurerm_subnet.private-subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_interface" "frontend" {
  name                = "${local.name}-frontend-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private-subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "backend" {
  name                = "${local.name}-backend-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private-subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "frontend" {
  name = "${local.name}-frontend"
  size = "Standard_B1s"

  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  network_interface_ids = [ azurerm_network_interface.frontend.id ]
  
  computer_name   = "frontend"
  admin_username  = "adminuser"

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_azure.pub")
  }

  os_disk {
    caching               = "ReadWrite"
    storage_account_type  = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22.04-LTS"
    version   = "latest"
  }

  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "backend" {
  name = "${local.name}-backend"
  size = "Standard_B1s"

  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  network_interface_ids = [ azurerm_network_interface.backend.id ]
  
  computer_name   = "backend"
  admin_username  = "adminuser"

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_azure.pub")
  }

  os_disk {
    caching               = "ReadWrite"
    storage_account_type  = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22.04-LTS"
    version   = "latest"
  }

  tags = local.tags
}

resource "azurerm_mysql_server" "mysql" {
  name                = "mysql"

  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  sku_name    = "B_Gen5_1"
  storage_mb  = 5120
  version     = "5.7"
  
  administrator_login           = "mysqladmin"
  administrator_login_password  = "password@1234"

  backup_retention_days   = 7
  ssl_enforcement_enabled = true
}
