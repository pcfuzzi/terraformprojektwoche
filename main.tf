# deklaration der ressourcen gruppe und location
locals {
  Ressource_Group_Name     = "adriano-christmann-rg"
  Ressource_Group_Location = "North Europe"
  Ssh_Username             = "techstarter"
  Ssh_Password             = "techstarter2342!"
}

## resourcen gruppe erstellen
resource "azurerm_resource_group" "cicdproject" {
  name     = local.Ressource_Group_Name
  location = local.Ressource_Group_Location
}

# public ssh key
resource "azurerm_ssh_public_key" "sshkey" {
  name                = "adriano"
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name
  public_key          = file("./sshkey.pub")
  depends_on = [
    azurerm_resource_group.cicdproject
  ]
}


# jenkins public ip
resource "azurerm_public_ip" "jenkins_public_ip" {
  name                = "jenkins-public-ip"
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name
  allocation_method   = "Dynamic"
  depends_on = [
    azurerm_resource_group.cicdproject
  ]
}

# webserver public ip
resource "azurerm_public_ip" "webserver_public_ip" {
  name                = "webserver-public-ip"
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name
  allocation_method   = "Dynamic"
  depends_on = [
    azurerm_resource_group.cicdproject
  ]
}

# eigenes netzwerk
resource "azurerm_virtual_network" "main" {
  name                = "cicidproject-network"
  address_space       = ["10.0.0.0/16"]
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name
  depends_on = [
    azurerm_resource_group.cicdproject
  ]
}

# subnet
resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = local.Ressource_Group_Name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
  depends_on = [
    azurerm_virtual_network.main
  ]
}

# netzwerk für den jenkins
resource "azurerm_network_interface" "jenkins" {
  name                = "jenkins-nic"
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name

  ip_configuration {
    name                          = "cicdprojectnetwork"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jenkins_public_ip.id
  }
  depends_on = [
    azurerm_public_ip.jenkins_public_ip
  ]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "cicdproject-nsg"
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name
  depends_on = [
    azurerm_resource_group.cicdproject
  ]
}

resource "azurerm_network_security_rule" "sshd" {
  name                        = "sshd"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.Ressource_Group_Name
  network_security_group_name = azurerm_network_security_group.nsg.name

  depends_on = [
    azurerm_network_security_group.nsg
  ]
}

resource "azurerm_network_security_rule" "web" {
  name                        = "web"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.Ressource_Group_Name
  network_security_group_name = azurerm_network_security_group.nsg.name
  depends_on = [
    azurerm_network_security_group.nsg
  ]
}

resource "azurerm_network_security_rule" "allout" {
  name                        = "allout"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.Ressource_Group_Name
  network_security_group_name = azurerm_network_security_group.nsg.name
  depends_on = [
    azurerm_network_security_group.nsg
  ]
}
# netzwerk für den webserver
resource "azurerm_network_interface" "webserver" {
  name                = "webserver-nic"
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name

  ip_configuration {
    name                          = "cicdprojectnetwork"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.webserver_public_ip.id
  }
  depends_on = [
    azurerm_public_ip.webserver_public_ip
  ]
}

resource "azurerm_network_interface_security_group_association" "webservernsg" {
  network_interface_id      = azurerm_network_interface.webserver.id
  network_security_group_id = azurerm_network_security_group.nsg.id
  depends_on = [
    azurerm_network_interface.webserver,
    azurerm_network_security_group.nsg
  ]
}

resource "azurerm_network_interface_security_group_association" "jenkinsnsg" {
  network_interface_id      = azurerm_network_interface.jenkins.id
  network_security_group_id = azurerm_network_security_group.nsg.id
  depends_on = [
    azurerm_network_interface.jenkins,
    azurerm_network_security_group.nsg
  ]
}

# jenkins vm mit netzwerk und ip
resource "azurerm_linux_virtual_machine" "jenkins" {
  name                  = "jenkins-vm"
  location              = local.Ressource_Group_Location
  resource_group_name   = local.Ressource_Group_Name
  network_interface_ids = [azurerm_network_interface.jenkins.id]
  size                  = "Standard_B1s"
  computer_name         = "jenkins"
  admin_username        = local.Ssh_Username
  admin_password        = local.Ssh_Password

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
  os_disk {
    name                 = "jenkins-osdisk1"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    username   = local.Ssh_Username
    public_key = azurerm_ssh_public_key.sshkey.public_key
  }

  tags = {
    environment = "jenkins"
  }
  depends_on = [
    azurerm_network_interface.jenkins,
    azurerm_network_security_group.nsg,
    azurerm_ssh_public_key.sshkey,
    azurerm_resource_group.cicdproject
  ]
}

# webserver vm mit netzwerk und ip
resource "azurerm_linux_virtual_machine" "webserver" {
  name                  = "webserver-vm"
  location              = local.Ressource_Group_Location
  resource_group_name   = local.Ressource_Group_Name
  network_interface_ids = [azurerm_network_interface.webserver.id]
  size                  = "Standard_B1s"
  computer_name         = "webserver"
  admin_username        = local.Ssh_Username
  admin_password        = local.Ssh_Password

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "webserver-osdisk1"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    username   = local.Ssh_Username
    public_key = azurerm_ssh_public_key.sshkey.public_key
  }

  tags = {
    environment = "webserver"
  }
  depends_on = [
    azurerm_network_interface.jenkins,
    azurerm_network_security_group.nsg,
    azurerm_ssh_public_key.sshkey,
    azurerm_resource_group.cicdproject
  ]
}