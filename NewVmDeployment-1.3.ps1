#########################################################################################################################################
# Author: Matt Deller
# Script: New VM Deployment
# Version: 1.2
# Summary: This script deploys new VM's from CSV input and performs the following post-clone deployment tasks:
# 1. Set CPU/RAM
# 2. Set IP/DNS configuration based on input from CSV
# 3. Join the domain
# 4. Resize the C: drive (Only if > 80GB)
# 5. Add one or more disks (If necessary)
# Note: Please see HowTo.txt for instructions on filling out the CSV
# Note 2: PLEASE MAKE SURE YOU HAVE THE RESOURCES AVAILABLE FOR THE CHANGES YOU ARE ABOUT TO MAKE!!!
# Note 3: This has been tested to run with VMware vSphere PowerCLI 6.0 Release 1 build 2548067
# 		  \\nasdata202\sharedata\IS-Server\SOFTWARE\VMWare\VMWare Power CLI 6.0 Powershell Snapin\VMware-PowerCLI-6.0.0-2548067.exe
#########################################################################################################################################

#Load PowerCLI environment if not already loaded
if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
. “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”
}
cls

Write-Host "Preparing to deploy VMs.  Please make sure your CSV file is accurate."

$vcentername = "sykvcenter02v"
$guestUser = Read-Host "Please Enter a Username (pa_) with admin privileges on the VM(s)"
$guestPass = Read-Host "Enter Password" -AsSecureString
$guestUser = "NSLIJHS\" + $guestUser
$Path = ".\DeployVM.csv"
$Servers = import-csv DeployVM.csv
$totalServers = @($Servers).Count
$timeout = 1800
$loop_control = 0

#Check to see if csv is in same folder as script
If(Test-Path -path $Path){}
else{write-host "DeployVM.csv is missing from the folder, do not run this from the network" ; exit}
#Add up the resources required and issue a warning before continuing
$driveSpaceTotal=0
$cpuTotal=0
$memTotal=0
foreach ($Server in $Servers)
{
	$cpuTotal += ($Server.CPU | Measure-Object -Sum).sum
	$memTotal += ($Server.RAM | Measure-Object -Sum).sum
	$driveSpaceTotal += ($Server.Cdrive | Measure-Object -Sum).sum += ($Server.Edrive | Measure-Object -Sum).sum += ($Server.Fdrive | Measure-Object -Sum).sum += ($Server.Gdrive | Measure-Object -Sum).sum += ($Server.Hdrive | Measure-Object -Sum).sum += ($Server.Idrive | Measure-Object -Sum).sum += ($Server.Jdrive | Measure-Object -Sum).sum += ($Server.Kdrive | Measure-Object -Sum).sum += ($Server.Ldrive | Measure-Object -Sum).sum += ($Server.Mdrive | Measure-Object -Sum).sum += ($Server.Ndrive | Measure-Object -Sum).sum += ($Server.Odrive | Measure-Object -Sum).sum += ($Server.Pdrive | Measure-Object -Sum).sum += ($Server.Qdrive | Measure-Object -Sum).sum += ($Server.Rdrive | Measure-Object -Sum).sum += ($Server.Sdrive | Measure-Object -Sum).sum += ($Server.Tdrive | Measure-Object -Sum).sum += ($Server.Udrive | Measure-Object -Sum).sum += ($Server.Vdrive | Measure-Object -Sum).sum += ($Server.Wdrive | Measure-Object -Sum).sum += ($Server.Xdrive | Measure-Object -Sum).sum += ($Server.Ydrive | Measure-Object -Sum).sum += ($Server.Zdrive | Measure-Object -Sum).sum
}
Write-Host "Warning: You are about to add " -foregroundcolor yellow -NoNewline; Write-Host $totalServers -foregroundcolor Red -NoNewline;Write-Host " VM's with a total of " -ForegroundColor Yellow -NoNewline;Write-Host $cpuTotal -ForegroundColor Red -NoNewline;Write-Host " virtual CPU's, " -ForegroundColor Yellow -NoNewline;Write-Host $memTotal -ForegroundColor Red -NoNewline;Write-Host "GB RAM and " -ForegroundColor Yellow -NoNewline;Write-Host $driveSpaceTotal -ForegroundColor Red -NoNewline;Write-Host "GB disk space to the environment." -ForegroundColor Yellow
Write-Host "Please ensure you have sufficient resources before continuing." -ForegroundColor Yellow
Write-Host "Press any key when you are ready to continue ..." -ForegroundColor Magenta
$x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") #Continue on any key press
#Connect to VCenter
Write-Host "Please wait, connecting to" $vcentername "This may take a minute."
connect-viserver $vcentername -wa 0

#For loop for each VM
foreach ($Server in $Servers)
{
	$DSCluster = Get-DatastoreCluster -Name $Server.DatastoreCluster
	$VmTemplate = Get-Template $Server.Template
	$VmCluster = Get-Cluster -Name $Server.Cluster
	$osspec = Get-OSCustomizationSpec AutoDeployScript
	Write-Host "Now deploying" $Server.Name -ForegroundColor Yellow
	New-VM -Name $Server.Name -ResourcePool $VmCluster -OSCustomizationSpec $osspec -Datastore $DSCluster -Template $VmTemplate -Location $Server.Folder
	Set-VM -VM $Server.Name -MemoryGB $Server.RAM -NumCpu $Server.CPU -Notes $Server.Notes -Confirm:$false
	get-vm -Name $Server.Name | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $Server.Network -confirm:$false
	#Track Deployment Progress
	$loop_control = 0
	write-host "Starting VM" $Server.name -ForegroundColor magenta
    start-vm -vm $Server.Name -confirm:$false | Out-Null
	#Wait for first boot
	write-host "Waiting for first boot of " $Server.Name -ForegroundColor yellow
    do
	{
    	$toolsStatus = (Get-VM -name $Server.name).extensiondata.Guest.ToolsStatus
        Start-Sleep 3
		$loop_control++
	}
	until ( ($toolsStatus -match ‘toolsOk’) -or ($toolsStatus -match ‘toolsOld’) -or ($loop_control -gt $timeout) )
 	#Wait for OS Customization to start
	write-host "Waiting for customization spec to apply for" $Server.Name -ForegroundColor Green
    do
	{
		$toolsStatus = (Get-VM -name $Server.Name).extensiondata.Guest.ToolsStatus
		Start-Sleep 3
		$loop_control++
    }
	until ( ($toolsStatus -match ‘toolsNotRunning’) -or ($loop_control -gt $timeout) )
 	#Wait for OS customization to finish
	Write-Host "OS customization in progress for" $Server.Name -ForegroundColor cyan
    do
	{
    	$toolsStatus = (Get-VM -name $Server.Name).extensiondata.Guest.ToolsStatus
		Start-Sleep 3
		$loop_control++
	}
	until ( ($toolsStatus -match ‘toolsOk’) -or ($toolsStatus -match ‘toolsOld’) -or ($loop_control -gt $timeout) )
#wait another minute "just in case"
Start-Sleep 60
#Clean-up the cloned OS Customization spec
#Remove-OSCustomizationSpec -CustomizationSpec specClone -Confirm:$false | Out-Null
#Check if VM Tools need updating
$toolsStatus = (Get-VM -name $Server.Name).extensiondata.Guest.ToolsStatus
if ($toolsStatus -match 'toolsOld')
{
	Write-Host "VM tools on template" $Server.Template "are out of date. Updating VM Tools"
	Update-Tools -VM $Server.Name
	Start-Sleep 60
}
else {}
do
{
   	$toolsStatus = (Get-VM -name $Server.name).extensiondata.Guest.ToolsStatus
	Start-Sleep 3
	$loop_control++
}
until ( ($toolsStatus -match ‘toolsOk’) -or ($loop_control -gt $timeout) )
#Set IP, Join Domain, Activate
if ($Server.SubnetMask -match "255.255.255.0")
{
	$PrefixLength = 24
}
elseif ($Server.SubnetMask -match "255.255.254.0")
{
	$PrefixLength = 23
}
elseif ($Server.SubnetMask -match "255.255.255.128")
{
	$PrefixLength = 25
}
else 
{}
$vmos = get-vmguest -vm $Server.Name
$vmname = $Server.Name
$vmip = $Server.IPAddress
$vmgw = $Server.Gateway
$PrDNS = $Server.pDNS
$SeDNS = $Server.sDNS
$dnsstring = '("' + $PrDNS + '","' + $SeDNS + '")'
If ($vmos.OsFullName -match "2012")
{
	invoke-vmscript -vm $Server.Name -scripttype PowerShell -scripttext "Get-NetAdapter -Name Ethernet0| Set-NetIPInterface -Dhcp Disabled" -guestuser "administrator" -guestpassword '2@six$A#'
	Write-Host "Setting IP" $vmip
	invoke-vmscript -vm $Server.Name -scripttype PowerShell -scripttext "Get-NetAdapter -Name Ethernet0| New-NetIPAddress -AddressFamily IPv4 -IPAddress $vmip -PrefixLength $PrefixLength -DefaultGateway $vmgw" -guestuser "administrator" -guestpassword '2@six$A#'
	Write-Host "Setting DNS servers" $PrDNS $SeDNS
	invoke-vmscript -vm $Server.Name -scripttype PowerShell -scripttext "Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses $dnsstring" -guestuser "administrator" -guestpassword '2@six$A#'
}
else
{
	Write-Host "Setting IP" $vmip "and DNS servers" $PrDNS $SeDNS
	get-vm -name $Server.Name | get-vmguestnetworkinterface -guestuser "administrator" -guestpassword '2@six$A#' | ? {$_.ippolicy -eq "DHCP"} | set-vmguestnetworkinterface -guestuser "administrator" -guestpassword '2@six$A#' -ippolicy static -ip $Server.IPAddress -netmask $Server.SubnetMask -gateway $Server.Gateway -DnsPolicy Static -Dns $PrDNS,$SeDNS
}
start-sleep -s 15 #Wait 15 seconds for network before joining domain
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($guestPass)
$UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
#Join domain & reboot
invoke-vmscript -vm $Server.Name -scripttype bat -scripttext "netdom join $vmname /domain nslijhs.net /userd $guestUser /passwordd $UnsecurePassword /reboot" -guestuser "administrator" -guestpassword '2@six$A#'
Restart-vmguest -vm $Server.Name -confirm:$false | Out-Null
write-host "Waiting for reboot of " $Server.Name "after joining domain" -ForegroundColor yellow
    do
	{
    	start-sleep -s 15
		$toolsStatus = (Get-VM -name $Server.name).extensiondata.Guest.ToolsStatus
        Start-Sleep 3
		$loop_control++
	}
	until ( ($toolsStatus -match ‘toolsOk’) -or ($toolsStatus -match ‘toolsOld’) -or ($loop_control -gt $timeout) )
Start-Sleep 30 #waiting another 30 seconds just in case
Write-Host "Activating Windows" -ForegroundColor Green
#Local auth to activate
Invoke-VMScript -vm $Server.Name -ScriptText "cscript c:\windows\system32\slmgr.vbs /ato" -guestuser "administrator" -guestpassword '2@six$A#' -ScriptType BAT
#Domain auto to activate
#Invoke-VMScript -vm $Server.Name -ScriptText "cscript c:\windows\system32\slmgr.vbs /ato" -GuestUser $guestUser -GuestPassword $guestPass -ScriptType BAT
#Check if we are resizing C: 
	if([int]$Server.Cdrive -gt 80)
	{
		#Resize the VMDK
		Get-HardDisk -vm $Server.Name | where {$_.Name -eq "Hard Disk 1"} | Set-HardDisk -CapacityGB $Server.Cdrive -Confirm:$false
		# Invoke Diskpart script to extend the volume
		#Local auth to extend C:
		Invoke-VMScript -vm $Server.Name -ScriptText "echo rescan > c:\diskpart.txt && echo select vol c >> c:\diskpart.txt && echo extend >> c:\diskpart.txt && diskpart.exe /s c:\diskpart.txt" -guestuser "administrator" -guestpassword '2@six$A#' -ScriptType BAT
		#Domain auth to extend C:
		#Invoke-VMScript -vm $Server.Name -ScriptText "echo rescan > c:\diskpart.txt && echo select vol c >> c:\diskpart.txt && echo extend >> c:\diskpart.txt && diskpart.exe /s c:\diskpart.txt" -GuestUser $guestUser -GuestPassword $guestPass -ScriptType BAT
	}

#Put together list of disks to add
	$Disks=@()
	If ($Server.Bdrive -gt 0)
	{
		$Disks+=,@($Server.Bdrive,'B')
	}
	If ($Server.Edrive -gt 0)
	{
		$Disks+=,@($Server.Edrive,'E')
	}
	If ($Server.Fdrive -gt 0)
	{
		$Disks+=,@($Server.Fdrive,'F')
	}
	If ($Server.Gdrive -gt 0)
	{
		$Disks+=,@($Server.Gdrive,'G')
	}
	If ($Server.Hdrive -gt 0)
	{
		$Disks+=,@($Server.Hdrive,'H')
	}
	If ($Server.Idrive -gt 0)
	{
		$Disks+=,@($Server.Idrive,'I')
	}
	If ($Server.Jdrive -gt 0)
	{
		$Disks+=,@($Server.Jdrive,'J')
	}
	If ($Server.Kdrive -gt 0)
	{
		$Disks+=,@($Server.Kdrive,'K')
	}
	If ($Server.Ldrive -gt 0)
	{
		$Disks+=,@($Server.Ldrive,'L')
	}
	If ($Server.Mdrive -gt 0)
	{
		$Disks+=,@($Server.Mdrive,'M')
	}
	If ($Server.Ndrive -gt 0)
	{
		$Disks+=,@($Server.Ndrive,'N')
	}
	If ($Server.Odrive -gt 0)
	{
		$Disks+=,@($Server.Odrive,'O')
	}
	If ($Server.Pdrive -gt 0)
	{
		$Disks+=,@($Server.Pdrive,'P')
	}
	If ($Server.Qdrive -gt 0)
	{
		$Disks+=,@($Server.Qdrive,'Q')
	}
	If ($Server.Rdrive -gt 0)
	{
		$Disks+=,@($Server.Rdrive,'R')
	}
	If ($Server.Sdrive -gt 0)
	{
		$Disks+=,@($Server.Sdrive,'S')
	}
	If ($Server.Tdrive -gt 0)
	{
		$Disks+=,@($Server.Tdrive,'T')
	}
	If ($Server.Udrive -gt 0)
	{
		$Disks+=,@($Server.Udrive,'U')
	}
	If ($Server.Vdrive -gt 0)
	{
		$Disks+=,@($Server.Vdrive,'V')
	}
	If ($Server.Wdrive -gt 0)
	{
		$Disks+=,@($Server.Wdrive,'W')
	}
	If ($Server.Xdrive -gt 0)
	{
		$Disks+=,@($Server.Xdrive,'X')
	}
	If ($Server.Ydrive -gt 0)
	{
		$Disks+=,@($Server.Ydrive,'Y')
	}
	If ($Server.Zdrive -gt 0)
	{
		$Disks+=,@($Server.Zdrive,'Z')
	}
	
	If ($Server.DiskStorageFormat -eq "Thin"){ $format = "thin" }
	ElseIf ($Server.DiskStorageFormat -eq "EZThick"){ $format = "EagerZeroedThick" }
	$external_counter = 1 #Holds the disk # for diskpart.
	foreach ($Disk in $Disks)
	{
		#Create the new VMDK
		New-HardDisk -VM $Server.Name -CapacityGB $Disk[0] -StorageFormat $format
		#Put together the diskpart script to format/assign drive letter
		If ($Server.Format64k -eq '0') #Non DB, use default allocation unit size
		{
			$DPScript = "echo rescan > c:\diskpart.txt && echo select disk " + $external_counter + " >> c:\diskpart.txt && echo online disk >> c:\diskpart.txt && echo attributes disk clear readonly >> c:\diskpart.txt && echo clean >> c:\diskpart.txt && echo convert mbr >> c:\diskpart.txt && echo create partition primary >> c:\diskpart.txt && echo select part 1 >> c:\diskpart.txt && echo format fs=ntfs quick >> c:\diskpart.txt && echo assign letter " + $Disk[1] + " >> c:\diskpart.txt && diskpart.exe /s c:\diskpart.txt"
		}	
		ElseIf ($Server.Format64k -eq '1') #DB, use 64K allocation unit size
		{ 
			$DPScript = "echo rescan > c:\diskpart.txt && echo select disk " + $external_counter + " >> c:\diskpart.txt && echo online disk >> c:\diskpart.txt && echo attributes disk clear readonly >> c:\diskpart.txt && echo clean >> c:\diskpart.txt && echo convert mbr >> c:\diskpart.txt && echo create partition primary >> c:\diskpart.txt && echo select part 1 >> c:\diskpart.txt && echo format fs=ntfs unit=64K quick >> c:\diskpart.txt && echo assign letter " + $Disk[1] + " >> c:\diskpart.txt && diskpart.exe /s c:\diskpart.txt"
		}
		#Run the diskpart script inside the VM
		#Uses local auto to add disks
		Invoke-VMScript -vm $Server.Name -ScriptText $DPScript -guestuser "administrator" -guestpassword '2@six$A#' -ScriptType BAT
		#Uses domain auto to add disks
		#Invoke-VMScript -vm $Server.Name -ScriptText $DPScript -GuestUser $guestUser -GuestPassword $guestPass -ScriptType BAT
		#Increment the disk # for next diskpart pass
		$external_counter++
	}
	Write-Host "One final reboot to apply Group Policies.  Please manually move server to Active Server OU after validation" -ForegroundColor Green
	Start-Sleep 5
	Restart-vmguest -vm $Server.Name -confirm:$false | Out-Null
}

Disconnect-VIServer -Confirm:$false