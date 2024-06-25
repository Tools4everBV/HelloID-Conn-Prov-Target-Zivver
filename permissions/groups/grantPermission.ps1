################################################################
# HelloID-Conn-Prov-Target-Zivver-GrantPermission-Group
# PowerShell V2
################################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($actionContext.Configuration.isDebug) {
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

    process {
        try {
            $splatParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/scim/v2/$Endpoint"
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
            $PSCmdlet.ThrowTerminatingError($_)
        }
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
        }
        catch {
            $httpErrorObj.FriendlyMessage = "Received an unexpected response. The JSON could not be converted, error: [$($_.Exception.Message)]. Original error from web service: [$($ErrorObject.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion functions

try {
    #region Verify account reference
    $actionMessage = "verifying account reference"
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw "The account reference could not be found"
    }
    #endregion Verify account reference

    #region Create authorization headers
    $actionMessage = "creating authorization headers"

    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.Token)")
    Write-Verbose "Created authorization headers"
    #endregion Create authorization headers

    #region Get Zivver account
    $actionMessage = "querying Zivver account"

    $getZivverSplatParams = @{
        Headers  = $headers
        Endpoint = "Users/$($actionContext.References.Account)"
        Method   = 'GET'
    }
    try {
        $correlatedAccount = Invoke-ZivverRestMethod @getZivverSplatParams
    }
    catch {
        # A '400'bad request is returned if the entity cannot be found
        if ($_.Exception.Response.StatusCode -eq 400) {
            $correlatedAccount = $null
        }
        else {
            throw
        }
    }
    Write-Verbose "Queried Ziver account where [id] = [$($actionContext.References.Account)]. Result: $($correlatedAccount | ConvertTo-Json)"
    #endregion Get Zivver account

    #region Get Zivver group
    $actionMessage = "querying Zivver group"

    $getZivverGroupSplatParams = @{
        Headers  = $headers
        Endpoint = "Groups/$($actionContext.References.Permission.Reference)"
        Method   = 'GET'
    }
    try {
        $correlatedGroup = Invoke-ZivverRestMethod @getZivverGroupSplatParams
    }
    catch {
        # A '400'bad request is returned if the entity cannot be found
        if ($_.Exception.Response.StatusCode -eq 400) {
            $correlatedGroup = $null
        }
        else {
            throw
        }
    }
    $currentGroupMembers = $correlatedGroup.members
    Write-Verbose "Queried Ziver group where [id] = [$($actionContext.References.Permission.Reference)]. Result: $($correlatedGroup | ConvertTo-Json)"
    #endregion Get Zivver group

    #region Calulate action
    $actionMessage = "calculating action"
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        if ($currentGroupMembers.value -contains $actionContext.References.Account) {
            $actionAccount = 'NoChanges'
        }
        else {
            $actionAccount = "GrantPermission"   
        }
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        $actionAccount = "MultipleFound"
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 0) {
        $actionAccount = "NotFound"
    }
    #endregion Calulate action

    #region Process
    switch ($actionAccount) {
        "GrantPermission" {
            #region grant permission
            $actionMessage = "granting permission"

            $memberToAdd = @{value = $actionContext.References.Account }
            $currentMembers += $memberToAdd
            [array]$updatedMembers = $currentMembers

            # Force object to an Array also if PS object only has one value.
            $updatedMembersJSON = ConvertTo-Json -InputObject @($updatedMembers)
            $body = @"
        {
    "schemas": [
        "urn:ietf:params:scim:api:messages:2.0:PatchOp"
    ],
    "Operations": [
        {
            "value": $updatedMembersJSON,
            "path": "members",
            "op": "replace"
        }
    ]
}
"@

            $putZivverSplatParams = @{
                Headers     = $headers
                Endpoint    = "Groups/$($actionContext.References.Permission.Reference)"
                Method      = 'PATCH'
                ContentType = 'application/scim+json'
                Body        = $body #| ConvertTo-Json
            }

            Write-Verbose "SplatParams: $($putZivverSplatParams | ConvertTo-Json)"

            if (-Not($actionContext.DryRun -eq $true)) {
                $null = Invoke-ZivverRestMethod @putZivverSplatParams

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Permission with displayName [$($actionContext.References.Permission.DisplayName)] and PermissionReference [$($actionContext.References.Permission.Reference)] granted to account with userName [$($correlatedAccount.userName)] and AccountReference [$($actionContext.References.Account)]."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would grant permission with displayName [$($actionContext.References.Permission.DisplayName)] and PermissionReference [$($actionContext.References.Permission.Reference)] to account with userName [$($correlatedAccount.userName)] and AccountReference [$($actionContext.References.Account)]."
            }
            #endregion grant permission

            break
        }

        'NoChanges' {
            #region NoChanges to group
            $actionMessage = "granting permission"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Permission with displayName [$($actionContext.References.Permission.DisplayName)] and PermissionReference [$($actionContext.References.Permission.Reference)] already granted to account with userName [$($correlatedAccount.userName)] and AccountReference [$($actionContext.References.Account)]."
                    IsError = $false
                })
            #endregion NoChanges to group

            break
        }


        "MultipleFound" {
            #region Multiple accounts found
            $actionMessage = "granting permission"

            # Throw terminal error
            throw "Multiple accounts found with AccountReference [$($actionContext.References.Account)]. Please correct this so the persons are unique."
            #endregion Multiple accounts found

            break
        }

        "NotFound" {
            #region No account found
            $actionMessage = "granting permission"
        
            # Throw terminal error
            throw "Account with AccountReference [$($actionContext.References.Account)] not found. Possibly indicating that it could be deleted, or not correlated."
            #endregion No account found

            break
        }
    }
    #endregion Process
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-ZivverError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
    else {
        $outputContext.Success = $true
    }
}