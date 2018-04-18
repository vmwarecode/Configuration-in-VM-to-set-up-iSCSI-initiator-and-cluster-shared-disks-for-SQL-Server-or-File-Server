# Enable cluster feature on Windows server to be as SQL Server Failover Clustering node.
Install-WindowsFeature -Name Failover-Clustering -IncludeAllSubFeature
Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools

# Enable Windows MPIO feature and explicitly set the failover policy to “Failover Only”
# Use the sample code below to enable Windows MPIO feature and explicitly set the failover policy to “Failover Only”

Get-WindowsOptionalFeature -Online -FeatureName MultiPathIO
Install-WindowsFeature -name Multipath-IO
Enable-WindowsOptionalFeature -Online -FeatureName MultiPathIO -NoRestart
Enable-MSDSMAutomaticClaim -BusType iSCSI

# Set up the MPIO interval
Set-MPIOSetting -CustomPathRecovery Enabled -NewPathRecoveryInterval 20 -NewRetryCount 60 -NewPDORemovePeriod 60 -NewPathVerificationPeriod 30 -NewDiskTimeout 60
# As iSCSI service only supports active/passive HA; we must set the load balance policy as failover only. Use the following script to enable automatic identification on FOO for vSAN iSCSI target
mpclaim -l -t "VMware  Virtual SAN     "  1



#Discover the target on each node of the Windows cluster and connect them
#Use the sample code below to discover the target on each node of the cluster and connect them using multiple connections for failover purpose. 
#Note: replace the IP address of the iSCSI vmk kernel IP address.  We use four hosts with vmk kernel ip address as an example.

$IPS='10.10.10.10','10.10.10.11','10.10.10.12','10.10.10.13'
foreach ($ip in $IPS){New-ISCSItargetportal -TargetPortalAddress $ip}
$targets=get-iSCSItarget | where isconnected -eq $False
$targets=get-iSCSItarget | where NodeAddress -like '*vmware:fs*'
$LocaliSCSIAddress=Get-NetIPAddress -AddressState  preferred -AddressFamily IPv4 -InterfaceAlias Ethernet0 -SkipAsSource $false |select -ExpandProperty IPAddress
Foreach ($ip in $IPS){
foreach ($tgt in $targets)
{
 Connect-ISCSITarget  -IsMultipathEnabled $true -TargetPortalAddress $ip -InitiatorPortalAddress $LocaliSCSIAddress -IsPersistent $true -nodeaddress $tgt.nodeaddress
}
}

# Create the Windows cluster on node of the Windows cluster, test the nodes and create the cluster. We use two node cluster as an example.
Test-Cluster -Node “Windows_cluster_node1”, “Windows_cluster_node2”
New-Cluster -Name “Windows_Cluster_name” -Node “Windows_cluster_node1” “Windows_cluster_node2” -StaticAddress “static_ip_address”

#Format the disks
#You may use the script below to format disks and we recommend using friendly name and serial number to filter out the disks from vSAN iSCSI service.

Get-disk| Where-Object {($_.FriendlyName -like '*VMware Virtual SAN*') -and ($_.SerialNumber -like '*VITSERIAL*')} |
 initialize-disk -partitionstyle mbr -passthru |
    new-partition -assigndriveletter -usemaximumsize |
      format-volume -filesystem ntfs -AllocationUnitSize 65536 -confirm:$False

# Add disks to Windows cluster and get ready for usage for SQL Server or File Server
Get-ClusterAvailableDisk |Add-ClusterDisk