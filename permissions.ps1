#############################################
# HelloID-Conn-Prov-Target-Zivver-Permissions
#
# Version: 1.1.0
#############################################
# Initialize default values
$config = $configuration | ConvertFrom-Json

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

        if ($Body){
            Write-Verbose 'Adding body to request'
            $utf8Encoding = [System.Text.Encoding]::UTF8
            $encodedBody = $utf8Encoding.GetBytes($body)
            $splatParams['Body'] = $encodedBody
        }
        Invoke-RestMethod @splatParams -Verbose:$false
    } catch {
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
        } catch {
            $httpErrorObj.FriendlyMessage = "Received an unexpected response. The JSON could not be converted, error: [$($_.Exception.Message)]. Original error from web service: [$($ErrorObject.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Verbose 'Setting authorization header'
    $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
    $headers.Add("Authorization", "Bearer $($config.Token)")
    $splatParams = @{
        Headers = $headers
    }

    Write-Verbose 'Retrieving Zivver groups'
    $permissions = [System.Collections.Generic.List[object]]::new()
    $splatParams['Endpoint'] = 'Groups'
    $splatParams['Method'] = 'GET'
    $responseGroups = Invoke-ZivverRestMethod @splatParams

    foreach ($group in $responseGroups.resources){
        $permission = @{
            DisplayName = "$($group.displayName)"
            Identification = @{
                Reference = $group.id
            }
        }
        $permissions.Add($permission)
    }
    Write-Output $permissions | ConvertTo-Json -Depth 10
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-ZivverError -ErrorObject $ex
        $auditMessage = "Could not retrieve Zivver permissions. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not retrieve Zivver permissions. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}