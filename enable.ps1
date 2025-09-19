#################################################
# HelloID-Conn-Prov-Target-Zivver-Enable
# PowerShell V2
#################################################

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
    Write-Information "Queried Ziver account where [id] = [$($actionContext.References.Account)]. Result: $($correlatedAccount | ConvertTo-Json)"
    #endregion Get Zivver account

    #region Calulate action
    $actionMessage = "calculating action"
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        if ([string]$correlatedAccount.active -eq $actionContext.Data.active) {
            $actionAccount = "NoChanges"
        }
        else {
            $actionAccount = "Enable"
        }  
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 0) {
        $actionAccount = "NotFound"
    }
    #endregion Calulate action

    #region Process
    switch ($actionAccount) {
        "Enable" {
            #region Update account
            $actionMessage = "enabling account"

            $body = @{
                schemas                                                      = @(
                    'urn:ietf:params:scim:schemas:core:2.0:User',
                    'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User',
                    'urn:ietf:params:scim:schemas:zivver:0.1:User'
                )
                active  = $actionContext.Data.active
                    name  = [PSCustomObject]@{
                        formatted = $actionContext.Data.fullname
                }
            }

            $putZivverSplatParams = @{
                Headers  = $headers
                Endpoint = "Users/$($actionContext.References.Account)"
                Method   = 'PUT'
                Body     = $body | ConvertTo-Json
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $null = Invoke-ZivverRestMethod @putZivverSplatParams

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account with userName [$($correlatedAccount.userName)] and AccountReference: [$($actionContext.References.Account)] enabled."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would enable account with AccountReference [$($actionContext.References.Account)]."
            }

            break
        }
        
        "NoChanges" {
            #region No changes
            $actionMessage = "enabling account"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Account with userName [$($correlatedAccount.userName)] and AccountReference: [$($actionContext.References.Account)]  is already enabled."
                    IsError = $false
                })
            #endregion No changes

            break
        }

        "NotFound" {
            #region No account found
            $actionMessage = "enabling account"
        
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

        # Change mapping here
        # Define your mapping here for returning the correct data to HelloID
        $outputDataObject = [PSCustomObject]@{
            active = [string]$actionContext.Data.active # value is returned as boleaan
        }
        Write-Verbose "output data to HelloID: [$($outputDataObject | Convertto-json)]"
        $outputContext.Data = $outputDataObject
        
        # Define your mapping here for returning the correct previous data to HelloID
        $outputPreviousDataObject = [PSCustomObject]@{
            active = [string]$correlatedAccount.active # value is returned as boleaan
        }
        Write-Verbose "output previous data to HelloID: [$($outputPreviousDataObject | Convertto-json)]"
        $outputContext.PreviousData = $outputPreviousDataObject
    }
}