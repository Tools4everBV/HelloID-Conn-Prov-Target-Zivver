###################################################
# HelloID-Conn-Prov-Target-Zivver-Entitlement-Grant
#
# Version: 1.1.0
###################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$pRef = $permissionReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

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
#endregion functions

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
    
    $splatParams['Endpoint'] = "Groups/$($pRef.Reference)"
    $splatParams['Method'] = 'GET'
    $responseGroup = Invoke-ZivverRestMethod @splatParams

    $currentMembers = $responseGroup.members

    if ($currentMembers.value -contains $aRef) {

        $action = 'NoChanges'

        $dryRunMessage = "[DryRun] Grant Zivver entitlement: [$($pRef.Reference)] to: [$($p.DisplayName)] already granted"
    }
    else {
        $memberToAdd = @{value = $aRef }
        $currentMembers += $memberToAdd
        [array]$updatedMembers = $currentMembers

        $action = 'Grant'

        $dryRunMessage = "[DryRun] Grant Zivver entitlement: [$($pRef.Reference)] to: [$($p.DisplayName)] will be executed during enforcement"
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning $dryRunMessage
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Grant' {
                Write-Verbose "Granting Zivver entitlement: [$($pRef.Reference)]"

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

                $splatParams['Endpoint'] = "Groups/$($pRef.Reference)"
                $splatParams['Method'] = 'PATCH'
                $splatParams['ContentType'] = 'application/scim+json'
                $splatParams['Body'] = $body

                $null = Invoke-ZivverRestMethod @splatParams

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Grant Zivver entitlement: [$($pRef.Reference)] was successful"
                        IsError = $false
                    })
            }
            'NoChanges' {
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Grant Zivver entitlement: [$($pRef.Reference)] was successful (already granted)"
                        IsError = $false
                    })
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
        $auditMessage = "Could not grant Zivver account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not grant Zivver account. Error: $($ex.Exception.Message)"
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
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}