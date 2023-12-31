########################################
# HelloID-Conn-Prov-Target-Zivver-Update
#
# Version: 1.1.0
########################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
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

# Account mapping
# The account object within Zivver contains a few more properties. For example, [delegates].
# These are not managed by HelloID and therefore, not listed in the account object.
$account = [PSCustomObject]@{
    name  = [PSCustomObject]@{
        formatted = Get-FullName -person $p
    }
    # 'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User' = [PSCustomObject]@{
    #     division = $p.PrimaryContract.Department.DisplayName
    # }
    'urn:ietf:params:scim:schemas:zivver:0.1:User' = [PSCustomObject]@{
        SsoAccountKey = $p.Accounts.MicrosoftActiveDirectory.UserPrincipalName
        # aliases = @()
    }
    userName = $p.Accounts.MicrosoftActiveDirectory.UserPrincipalName 
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
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [ValidateNotNullOrEmpty()]
        [string]
        $Endpoint,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json',

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

        if ($Body) {
            Write-Verbose 'Adding body to request'
            $utf8Encoding = [System.Text.Encoding]::UTF8
            $encodedBody = $utf8Encoding.GetBytes($body)
            $splatParams['Body'] = $encodedBody
        }
        Invoke-RestMethod @splatParams -Verbose:$false
    }
    catch {
        Throw $_
    }
}

function Resolve-ZivverError {
    param (
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
        }
        catch {
            $httpErrorObj.FriendlyMessage = "Received an unexpected response. The JSON could not be converted, error: [$($_.Exception.Message)]. Original error from web service: [$($ErrorObject.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}

function Compare-ZivverAccountObject {
    param (
        [object]
        $ReferenceObject,

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
        }
        elseif ($referenceValue -is [Array] -and $differenceValue -is [Array]) {
            if (-not (Compare-Array $referenceValue $differenceValue)) {
                $differences += $key
                if ($key -eq "urn:ietf:params:scim:schemas:zivver:0.1:User") {
                    $array1 = $referenceValue -join ","
                    $array2 = $differenceValue -join ","
                    $differences += "Array1: $array1"
                    $differences += "Array2: $array2"
                }
            }
        }
        elseif ($referenceValue -ne $differenceValue) {
            $differences += $key
        }
    }

    Write-Output $differences
}

function Compare-Array {
    param (
        [object]
        $ReferenceObject,

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
    Write-Verbose "Verify if [$aRef] has a value"
    if ([string]::IsNullOrEmpty($($aRef))) {
        throw 'Mandatory attribute [aRef] is empty.'
    }

    Write-Verbose 'Creating authorization header'
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($config.Token)")
    $splatParams = @{
        Headers = $headers
    }

    try {
        Write-Verbose "Verifying if a Zivver account for [$($p.DisplayName)] exists"
        $splatParams['Endpoint'] = "Users/$aRef"
        $splatParams['Method'] = 'GET'
        $responseUser = Invoke-ZivverRestMethod @splatParams
    }
    catch {
        # A '400'bad request is returned if the entity cannot be found
        if ($_.Exception.Response.StatusCode -eq 400) {
            $responseUser = $null
        }
        else {
            throw
        }
    }

    if ($responseUser.Length -lt 1) {
        throw "Zivver account for: [$($p.DisplayName)] not found. Possibly deleted"
    }

    Write-Verbose "Verify if Zivver account for [$($p.DisplayName)] must be updated"
    $splatCompareProperties = @{
        ReferenceObject   = @($responseUser)
        DifferenceObject  = @($account)
        ExcludeProperties = @("delegates", "id", "meta", "active", "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User", "urn:ietf:params:scim:schemas:zivver:0.1:User", "schemas") # Properties not managed by HelloID, are excluded from the comparison.
    }
    $propertiesChanged = Compare-ZivverAccountObject @splatCompareProperties

    if ($propertiesChanged) {
        # Create the JSON body for the properties to update

        if ($account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.PSObject.Properties.Name -contains 'SsoAccountKey') {
            $responseUser.'urn:ietf:params:scim:schemas:zivver:0.1:User' | Add-Member -MemberType NoteProperty -Name "SsoAccountKey" -Value $account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.SsoAccountKey -Force
        }

        $responseUser.name.formatted = $account.name.formatted

        if ($account.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.PSObject.Properties.Name -contains 'division') {
            $responseUser.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division = $account.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
        }

        if ($account.PSObject.Properties.Name -contains 'userName') {
            $responseUser.userName = $account.userName
        }

        $action = 'Update'
        $dryRunMessage = "Update Zivver account for: [$($p.DisplayName)], will be executed during enforcement. Account property(s) required to update: [$($propertiesChanged -join ", ")]"
    }
    else {
        $action = 'NoChanges'
        $dryRunMessage = 'No changes will be made to the account during enforcement'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Update' {
                Write-Verbose "Updating Zivver account with accountReference: [$aRef]"
                $splatParams['Endpoint'] = "Users/$aRef"
                $splatParams['Method'] = 'PUT'
                $splatParams['Body'] = $responseUser | ConvertTo-Json
                $null = Invoke-ZivverRestMethod @splatParams

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Update account was successful'
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to Zivver account with accountReference: [$aRef]"

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = "No changes to Zivver account with accountReference: [$aRef]"
                        IsError = $false
                    })
                break
            }
        }
    }
}
catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-ZivverError -ErrorObject $ex
        $auditMessage = "Could not update Zivver account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not update Zivver account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
}
finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Account   = $account
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}