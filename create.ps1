#################################################
# HelloID-Conn-Prov-Target-Zivver-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($actionContext.Configuration.isDebug) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region mapping
# Change mapping here
$account = [PSCustomObject]@{
    schemas                                                      = @(
        'urn:ietf:params:scim:schemas:core:2.0:User',
        'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User',
        'urn:ietf:params:scim:schemas:zivver:0.1:User'
    )
    active                                                       = $actionContext.Data.active
    name                                                         = [PSCustomObject]@{
        formatted = $actionContext.Data.fullname
    }
    'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User' = [PSCustomObject]@{
        division = $actionContext.Data.division # If the division can't be found within Zivver, an error will be thrown (By Zivver). Error: Invalid division: {name of division}
    }
    'urn:ietf:params:scim:schemas:zivver:0.1:User'               = [PSCustomObject]@{
        SsoAccountKey = $actionContext.Data.ssoAccountKey
        # aliases = @()
    }
    userName                                                     = $actionContext.Data.userName
}
#endregion mapping

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
    #region Verify correlation configuration and properties
    $actionMessage = "verifying correlation configuration and properties"

    if ($actionContext.CorrelationConfiguration.Enabled -eq $true) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue
        if ([string]::IsNullOrEmpty($correlationField)) {
            throw "Correlation is enabled but not configured correctly."
        }
        
        if ([string]::IsNullOrEmpty($correlationValue)) {
            throw "The correlation value for [$correlationField] is empty. This is likely a mapping issue."
        }
    }
    else {
        throw "Configuration of correlation is madatory."
    }
    #endregion Verify correlation configuration and properties
    
    #region Create authorization headers
    $actionMessage = "creating authorization headers"

    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.Token)")
    #endregion Create authorization headers

    #region Get Zivver account
    $actionMessage = "querying Zivver account"

    $getZivverSplatParams = @{
        Headers  = $headers
        Endpoint = "Users?filter=$correlationField eq ""$correlationValue"""
        Method   = 'GET'
    }

    $correlatedAccount = (Invoke-ZivverRestMethod @getZivverSplatParams).Resources
        
    Write-Information "Queried Ziver account where [$($correlationField)] = [$($correlationValue)]. Result: $($correlatedAccount | ConvertTo-Json)"
    #endregion Get Zivver account

    #region Calulate action
    $actionMessage = "calculating action"
    if (($correlatedAccount | Measure-Object).count -eq 0) {
        $actionAccount = "Create"
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 1) {
        $actionAccount = "Correlate"
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        $actionAccount = "MultipleFound"
    }
    #endregion Calulate action

    #region Process
    switch ($actionAccount) {
        "Create" {
            $actionMessage = "creating account"
            # Create account with only required fields

            $postZivverSplatParams = @{
                Headers  = $headers
                Endpoint = 'Users'
                Method   = 'POST'
                Body     = $account | ConvertTo-Json
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $createdAccount = Invoke-ZivverRestMethod @postZivverSplatParams

                $outputContext.AccountReference = $createdAccount.id
                $outputData = $createdAccount


                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account with userName [$($createdAccount.userName)] and AccountReference [$($outputContext.AccountReference)] created."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would create account with userName [$($actionContext.Data.userName)]."
            }

            break
        }

        "Correlate" {
            $actionMessage = "correlating to account"

            $outputContext.AccountReference = $correlatedAccount.id
            $outputData = $correlatedAccount

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount" # Optionally specify a different action for this audit log
                    Message = "Account with userName [$($correlatedAccount.userName)] and AccountReference [$($outputContext.AccountReference)] correlated on [$($correlationField)] = [$($correlationValue)]."
                    IsError = $false
                })

            $outputContext.AccountCorrelated = $true

            break
        }

        "MultipleFound" {
            $actionMessage = "correlating to account"

            # Throw terminal error
            throw "Multiple accounts found where [$($correlationField)] = [$($correlationValue)]. Please correct this so the persons are unique."

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
        
        # Change mapping here
        # Define your mapping here for returning the correct data to HelloID
        $outputDataObject = [PSCustomObject]@{
            id            = $outputData.id
            active        = [string]$outputData.active # value is returned as boleaan
            fullname      = $outputData.name.formatted
            division      = $outputData.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
            ssoAccountKey = $account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.ssoAccountKey # ssoAccountKey is not returned by Zivver, account is mapped to make sure the same value is returned
            userName      = $outputData.userName
        }
        Write-Verbose "output data to HelloID: [$($outputDataObject | Convertto-json)]"
        $outputContext.Data = $outputDataObject
    }

    # Check if accountreference is set, if not set, set this with default value as this must contain a value
    if ([String]::IsNullOrEmpty($outputContext.AccountReference) -and $actionContext.DryRun -eq $true) {
        $outputContext.AccountReference = "DryRun: Currently not available"
    }
}