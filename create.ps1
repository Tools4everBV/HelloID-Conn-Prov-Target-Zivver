########################################
# HelloID-Conn-Prov-Target-Zivver-Create
#
# Version: 1.0.0
########################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

#region support functions
function Get-FullName {
    Param (
        [object]$person
    )

    if ([string]::IsNullOrEmpty($p.Name.Nickname)) { $calcFirstName = $p.Name.GivenName } else { $calcFirstName = $p.Name.Nickname }

    $calcFullName = $calcFirstName + ' '

    switch ($person.Name.Convention) {
        'B' { 
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyName
            break 
        }
        'P' { 
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePartnerPrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePartnerPrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyNamePartner
            break 
        }
        'BP' { 
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyName + ' - '
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePartnerPrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePartnerPrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyNamePartner
            break 
        }
        'PB' { 
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePartnerPrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePartnerPrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyNamePartner + ' - '
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyName
            break 
        }
        Default {
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyName
            break 
        }
    } 
    return $calcFullName
}
#endregion support functions

# Account mapping -
$account = [PSCustomObject]@{
    schemas = @(
        'urn:ietf:params:scim:schemas:core:2.0:User',
        'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User',
        'urn:ietf:params:scim:schemas:zivver:0.1:User'
    )
    active  = $false
    name = [PSCustomObject]@{
        formatted = Get-FullName -person $p
    }
    'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User' = [PSCustomObject]@{
        division = $p.PrimaryContract.Department.DisplayName
    }
    'urn:ietf:params:scim:schemas:zivver:0.1:User' = [PSCustomObject]@{
        #SsoAccountKey = ''
        aliases = @()
    }
    userName = $p.Accounts.MicrosoftActiveDirectory.mail
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Invoke-ZivverRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Endpoint,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json',

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )

    try {
        $splatParams = @{
            Uri         = "$($config.BaseUrl)/api/scim/v2/$Endpoint"
            Headers     = $Headers
            Method      = $Method
            ContentType = $ContentType
        }

        if ($Body){
            Write-Verbose 'Adding body to request'
            $utf8Encoding = [System.Text.Encoding]::UTF8
            $encodedBody = $utf8Encoding.GetBytes($body)
            $splatParams['Body'] = $encodedBody
        }
        Invoke-RestMethod @splatParams -Verbose:$false
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-ZivverError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        try {
            $errorDetails = $ErrorObject.ErrorDetails.Message
            $httpErrorObj.ErrorDetails = "Exception: $($ErrorObject.Exception.Message), Error: $($errorDetails)"
            $httpErrorObj.FriendlyMessage = "Error: $($errorDetails)"
        } catch {
            $httpErrorObj.FriendlyMessage = "Received an unexpected response. The JSON could not be converted, error: [$($_.Exception.Message)]. Original error from web service: [$($ErrorObject.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}

function Compare-ZivverAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ReferenceObject,

        [Parameter(Mandatory)]
        [object]
        $DifferenceObject,

        [array]
        $ExcludeProperties = @()
    )

    $differences = @()

    foreach ($key in $ReferenceObject | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) {
        if ($ExcludeProperties -contains $key) {
            continue
        }

        $referenceValue = $ReferenceObject.$key
        $differenceValue = $DifferenceObject.$key

        if ($referenceValue -is [PSCustomObject] -and $differenceValue -is [PSCustomObject]) {
            $nestedDifferences = Compare-ZivverAccountObject -ReferenceObject $referenceValue -DifferenceObject $differenceValue -ExcludeProperties $ExcludeProperties
            if ($nestedDifferences) {
                $differences += $key
                $differences += $nestedDifferences
            }
        } elseif ($referenceValue -is [Array] -and $differenceValue -is [Array]) {
            if (-not (Compare-Array $referenceValue $differenceValue)) {
                $differences += $key
                if ($key -eq "urn:ietf:params:scim:schemas:zivver:0.1:User") {
                    $array1 = $referenceValue -join ","
                    $array2 = $differenceValue -join ","
                    $differences += "Array1: $array1"
                    $differences += "Array2: $array2"
                }
            }
        } elseif ($referenceValue -ne $differenceValue) {
            $differences += $key
        }
    }

    Write-Output $differences
}

function Get-EmailAliasFromContract {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $Person
    )

    $aliasCollection = [System.Collections.Generic.List[object]]::new()
    $contractsSortedOnUniqueOrganization = $Person.Contracts | Sort-Object { $_.Organization.Name } -Unique
    foreach ($contract in $contractsSortedOnUniqueOrganization){
        if($contract.Context.InConditions){
            $organizationName = $contract.Organization.Name.ToLower()
            $alias = $account.userName -replace '(?<=@)[^.]+', $organizationName
            $alias = ($alias -replace '\s', '').ToLower() # Remove spaces from the email alias

            # Add the alias to the collection only if it is different from the person's business email
            if ($alias -ne $Person.Contact.Business.Email.ToLower()) {
                $aliasCollection.Add($alias)
            }
        }
    }
    Write-Output $aliasCollection
}

function Compare-Array {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ReferenceObject,

        [Parameter(Mandatory)]
        [object]
        $DifferenceObject
    )

    if ($ReferenceObject.Length -ne $DifferenceObject.Length) {
        return $false
    }

    $sortedArr1 = $ReferenceObject | Sort-Object
    $sortedArr2 = $DifferenceObject | Sort-Object

    for ($i = 0; $i -lt $sortedArr1.Length; $i++) {
        if ($sortedArr1[$i] -ne $sortedArr2[$i]) {
            return $false
        }
    }

    return $true
}
#endregion

# Begin
try {
    Write-Verbose "Verify if [$account.userName] has a value"
    if ([string]::IsNullOrEmpty($($account.userName))) {
        throw 'Mandatory attribute [$account.userName] is empty.'
    }

    Write-Verbose 'Creating authorization header'
    $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
    $headers.Add("Authorization", "Bearer $($config.Token)")
    $splatParams = @{
        Headers = $headers
    }

    Write-Verbose "Verifying if Zivver account for [$($p.DisplayName)] must be created or correlated"
    $splatParams['Endpoint'] = "Users?filter=userName eq ""$($account.userName)"""
    $splatParams['Method'] = 'GET'
    $responseUser = Invoke-ZivverRestMethod @splatParams

    if ($responseUser.Resources.Length -lt 1){
        $action = 'Create-Correlate'
        Write-Verbose 'Getting email aliases from person contracts'
        $desiredAliasesFromContracts = Get-EmailAliasFromContract -Person $p
        $account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.aliases += $desiredAliasesFromContracts
        $dryRunMessage = "Create Zivver account for: [$($p.DisplayName)], will be executed during enforcement. The aliases: [$($desiredAliasesFromContracts -join ', ')] will be added as Zivver email aliases."
    } elseif ($responseUser.Resources | Where-Object { $_.userName -eq $account.userName }){
        $action = 'Correlate'
        $dryRunMessage = "Correlate Zivver account for: [$($p.DisplayName)], will be executed during enforcement."

        if ($($config.UpdatePersonOnCorrelate -eq "true")){
            Write-Verbose 'Get current email aliases from contract and compare with what is already defined within Zivver'
            $desiredAliasesFromContracts = Get-EmailAliasFromContract -Person $p
            $currentAliasesInZivver = $responseUser.resources[0].'urn:ietf:params:scim:schemas:zivver:0.1:User'.aliases
            $account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.aliases += $currentAliasesInZivver

            foreach ($desiredAlias in $desiredAliasesFromContracts) {
                if ($currentAliasesInZivver -contains $desiredAlias) {
                    Write-Verbose "Desired alias [$desiredAlias] exists and will not be added to Zivver"
                } else {
                    Write-Verbose "Desired alias [$desiredAlias] does not exist and will be added to Zivver"
                    $account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.aliases += $desiredAlias
                }
            }

            Write-Verbose "Verify if Zivver account for [$($p.DisplayName)] must be updated"
            $splatCompareProperties = @{
                ReferenceObject  = @($responseUser.resources)
                DifferenceObject = @($account)
                ExcludeProperties = @("delegates","id", "meta") # Properties not managed by HelloID, are excluded from the comparison.
            }
            $propertiesChanged = Compare-ZivverAccountObject @splatCompareProperties

            if ($propertiesChanged) {
                # Create the JSON body for the properties to update
                $jsonBody = @{
                    "schemas" = @(
                        "urn:ietf:params:scim:schemas:core:2.0:User",
                        "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User",
                        "urn:ietf:params:scim:schemas:zivver:0.1:User"
                    )
                }

                if ($propertiesChanged -contains 'urn:ietf:params:scim:schemas:zivver:0.1:User'){
                    $jsonBody['urn:ietf:params:scim:schemas:zivver:0.1:User:aliases'] = @{
                        'aliases' = @($account.'urn:ietf:params:scim:schemas:zivver:0.1:User')
                    }
                }

                if ($propertiesChanged -contains 'name'){
                    $jsonbody['name'] = @{
                        'name.formatted' = $account.name.formatted
                    }
                }

                if ($propertiesChanged -contains 'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'){
                    $jsonbody['division'] = $account.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
                }

                $action = 'Update-OnCorrelate'
                $dryRunMessage = "Update Zivver account for: [$($p.DisplayName)], will be executed during enforcement. Account property(s) required to update: [$($propertiesChanged -join ", ")]"
            } else {
                $action = 'NoChanges'
                $dryRunMessage = 'No changes will be made to the account during enforcement'
            }
        }
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning $dryRunMessage
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose 'Creating and correlating Zivver account'
                $splatParams['Endpoint'] = 'Users'
                $splatParams['Method'] = 'POST'
                $splatParams['Body'] = $account | ConvertTo-Json
                $responseCreatedUser = Invoke-ZivverRestMethod @splatParams
                $accountReference = $responseCreatedUser.id
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Create-Correlate account was successful. AccountReference is: [$accountReference]"
                    IsError = $false
                })
                break
            }

            'Update-OnCorrelate' {
                Write-Verbose "Updating Zivver account with accountReference: [$($responseUser.Resources.id)]"
                $splatParams['Endpoint'] = "Users/$($responseUser.Resources.id)"
                $splatParams['Method'] = 'PUT'
                $splatParams['Body'] = $jsonBody | ConvertTo-Json
                $null = Invoke-ZivverRestMethod @splatParams

                $accountReference = $responseUser.Resources.id
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful. AccountReference is: [$accountReference]"
                    IsError = $false
                })
                break
            }

            'Correlate' {
                Write-Verbose 'Correlating Zivver account'
                $accountReference = $responseUser.Resources.id
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Correlate account was successful. AccountReference is: [$accountReference]"
                    IsError = $false
                })
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to Zivver account with accountReference: [$aRef]"
                $accountReference = $responseUser.Resources.id
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                    Message = "No changes have been made to the account during enforcement. AccountReference is: [$accountReference]"
                    IsError = $false
                })
                break
            }
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-ZivverError -ErrorObject $ex
        $auditMessage = "Could not $action Zivver account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not $action Zivver account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
# End
} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
