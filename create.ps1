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
    active = $true # mandatory value for Post, Remark Zivver always makes the user active when created. This value is used for 'Update-OnCorrelate'
    name = [PSCustomObject]@{
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
    $responseUser = (Invoke-ZivverRestMethod @splatParams).Resources

    if ($responseUser.Length -lt 1){
        $action = 'Create-Correlate'
        $dryRunMessage = "Create Zivver account for: [$($p.DisplayName)], will be executed during enforcement."
    } elseif ($responseUser | Where-Object { $_.userName -eq $account.userName }){
        $action = 'Correlate'
        $dryRunMessage = "Correlate Zivver account for: [$($p.DisplayName)], will be executed during enforcement."

        if ($($config.UpdatePersonOnCorrelate -eq "true")){
         
            # When correlate make user active
            $responseUser | Add-Member -MemberType NoteProperty -Name "active" -Value $account.active -Force

            if ($account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.PSObject.Properties.Name -contains 'SsoAccountKey') {
                $responseUser.'urn:ietf:params:scim:schemas:zivver:0.1:User' | Add-Member -MemberType NoteProperty -Name "SsoAccountKey" -Value $account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.SsoAccountKey -Force
            }

            $responseUser.name.formatted = $account.name.formatted

            if ($account.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.PSObject.Properties.Name -contains 'division') {
                $responseUser.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division = $account.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
            }

            $action = 'Update-OnCorrelate'
            $dryRunMessage = "Update Zivver account for: [$($p.DisplayName)], will be executed during enforcement."
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
                Write-Verbose "Updating Zivver account with accountReference: [$($responseUser.id)]"
                $splatParams['Endpoint'] = "Users/$($responseUser.id)"
                $splatParams['Method'] = 'PUT'
                $splatParams['Body'] = $responseUser | ConvertTo-Json
                $null = Invoke-ZivverRestMethod @splatParams

                $accountReference = $responseUser.id
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful. AccountReference is: [$accountReference]"
                    IsError = $false
                })
                break
            }

            'Correlate' {
                Write-Verbose 'Correlating Zivver account'
                $accountReference = $responseUser.id
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Correlate account was successful. AccountReference is: [$accountReference]"
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
        ExportData       = [PSCustomObject]@{
            id = $accountReference
        }
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}