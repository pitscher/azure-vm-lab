#
# This script will create or delete (optional param -deleteRoleAssignments "true") Azure Role Assignments for a set of Azure VMs.
# Each user will get a dedicated role assignment for a single Azure VM that belongs to him.
#
# This script was crafted to work alongside the Bicep definitions located in this repository.
# Make sure to set the same values e.g. for the tenant, subId, roleName, resourceGroupName
#

param(
  # Usually <userEmailHandle>@company.tld -> example: @company.tld / User Principal Name suffix. Check a users properties in EntraID to get the suffix value.
  [Parameter(Mandatory=$true)]
  $upnSuffix,

  # Usually <company>.onmicrosoft.com -> example: mycompany.onmicrosoft.com / the EntraID tenant ID will work, too.
  [Parameter(Mandatory=$true)]
  $tenant,

  # ID of the Azure subscription holding the VMs.
  [Parameter(Mandatory=$true)]
  $subscriptionId,

  # Full name of the RBAC role this script should use while creating role assignments.
  # IMPORTANT: If you want to assign a custom role, ensure it got created BEFORE running this script. This is (usually) done at the Azure subscription level.
  [Parameter(Mandatory=$true)]
  $roleName,

  # Name of the resource group holding the VMs of all users.
  [Parameter(Mandatory=$true)]
  $resourceGroupName,

  # Set this optional flag if you want to delete the previously created role assignments.
  [Parameter(Mandatory=$false)]
  $deleteRoleAssignments
)

# Stops script execution in case of an error
$ErrorActionPreference = "Stop"

# IMPORTANT: Ensure the custom role was created (if you want to assign one instead of a BuiltIn role) & the VMs are deployed!
# IMPORTANT: Add the users User Principal Name (UPN) without the suffix as it appears in Entra ID. Do not shorten them! The UPN usually equals the email account of a user.
#            Example: In your EntraID profile of your company, your UPN is "jdoe@company.com" -> your UPN without the company suffix (@company.com) is "jdoe".
#            HINT: It might be that the UPN (without suffix) of individual users is too long.
#                  Windows computer names in Azure are limited to 15 characters. The Bicep deployment will add the prefix "vmw-" to each VM.
#                  Result: The used UPN (without suffix) can be max 11 characters long. This script will shorten the UPN (without suffix) if required.
$vmUsers = @(
  'jdoe'
  'mmustermann'
)

Write-Host "[INFO] Attempting to sign into Azure..."
try {
  Connect-AzAccount -Tenant $tenant -Subscription $subscriptionId
}
catch {
  Throw "[ERR] Ran into an error while trying to sign into Azure. You need to install the Az PowerShell module before running this script. Error message: $_"
}
Write-Host "[OK] Signed into Azure"

if (($deleteRoleAssignments -eq $false) -OR ([string]::IsNullOrEmpty($deleteRoleAssignments))) {
  Write-Host "[INFO] Optional parameter -deleteRoleAssignments was not used. Will create Role Assignments..."
  $progressBarLabel = " Creating Role Assignments"
} else {
  Write-Host "[INFO] Optional parameter -deleteRoleAssignments was used. Will delete Role Assignments..."
  $progressBarLabel = " Deleting Role Assignments"
}

$counter = 0

foreach ($user in $vmUsers) {
  $upn = $user + $upnSuffix
  $shortenedUsername = $user[0..10] -join "" # Limits the length of a string to 11 chars and cuts it from the right if required. Strings shorter than max length will stay untouched.
  $vmName = "vmw-" + $shortenedUsername
  $scope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName"
  
  switch ($deleteRoleAssignments -eq "true") {
    $false {
      try {
        New-AzRoleAssignment -SignInName "$upn" -RoleDefinitionName "$roleName" -Scope "$scope"
      }
      catch {
        Throw "[ERR] Ran into an error while trying to create role assignments (created $counter before this exception happened). Error message: $_ | For debugging: UPN -> $upn / VM -> $vmName"
      }
      break
    }
    $true {
      try {
        Remove-AzRoleAssignment -SignInName "$upn" -RoleDefinitionName "$roleName" -Scope "$scope"
      }
      catch {
        Throw "[ERR] Ran into an error while trying to remove role assignments (removed $counter before this exception happened). Error message: $_ | For debugging: UPN -> $upn / VM -> $vmName"
      }
      break
    }
    Default { Throw "[ERR] Something unexpected happened which is most likely related to the optional parameter -deleteRoleAssignments" }
  }

  $counter++
  Write-Progress -Activity $progressBarLabel -Status " $([Math]::Round(($counter/$vmUsers.Count)*100))% / $counter complete | successfully processed: $upn" -PercentComplete $([Math]::Round(($counter/$vmUsers.Count)*100))
}
Write-Host "[OK] Done. Successfully processed $counter Role Assignments. Please note that Azure might need some time to process the changes."