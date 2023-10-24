####################################################
# HelloID-Conn-Prov-Target-Zivver-Entitlement-Revoke
#
# Version: 1.0.0
####################################################
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
    Write-Verbose "Verify if [$aRef] has a value"
    if ([string]::IsNullOrEmpty($($aRef))) {
        throw 'Mandatory attribute [aRef] is empty.'
    }

    Write-Verbose 'Creating authorization header'
    $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
    $headers.Add("Authorization", "Bearer $($config.Token)")
    $splatParams = @{
        Headers = $headers
    }

    Write-Verbose "Verifying if a Zivver account for [$($p.DisplayName)] exists"
    $splatParams['Endpoint'] = "Users/$aRef"
    $splatParams['Method'] = 'GET'
    $responseUser = Invoke-ZivverRestMethod @splatParams
    if ($null -ne $responseUser.Resources.Length -eq 1 -and $responseUser.Resources.userName -eq $($account.userName)){
        $action = 'Found'
        $dryRunMessage = "Revoke Zivver entitlement: [$($pRef.Reference)] to: [$($p.DisplayName)] will be executed during enforcement"
    } elseif ($responseUser.Resources.Length -lt 1){
        $action = 'NotFound'
        $dryRunMessage = "Zivver account for: [$($p.DisplayName)] not found. Possibly already deleted. Skipping action"
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action){
            'Found' {
                Write-Verbose "Revoking Zivver entitlement: [$($pRef.Reference)]"
                $body = [PSCustomObject]@{
                    operations = @(
                        @{
                            op    = "remove"
                            path  = "members"
                            value = @(
                                @{
                                    value = $aRef
                                }
                            )
                        }
                    )
                }
                $splatParams['Endpoint'] = "groups/$($pRef.Reference)"
                $splatParams['Method'] = 'PATCH'
                $splatParams['Body'] = $body | ConvertTo-Json
                $null = Invoke-ZivverRestMethod @splatParams

                $auditLogs.Add([PSCustomObject]@{
                    Message = "Revoke Zivver entitlement: [$($pRef.Reference)] was successful"
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Zivver account for: [$($p.DisplayName)] not found. Possibly already deleted. Skipping action"
                    IsError = $false
                })
                break
            }
        }

        $success = $true
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-ZivverError -ErrorObject $ex
        $auditMessage = "Could not revoke Zivver account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not revoke Zivver account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
# End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
