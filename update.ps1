#################################################
# HelloID-Conn-Prov-Target-Zivver-Update
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
    $outputPreviousData = $correlatedAccount.PsObject.Copy()
    Write-Verbose "Queried Ziver account where [id] = [$($actionContext.References.Account)]. Result: $($correlatedAccount | ConvertTo-Json)"
    #endregion Get Zivver account

    #region Calulate action
    $actionMessage = "calculating action"
    if (($correlatedAccount | Measure-Object).count -eq 1) {
        $actionMessage = "comparing current account to mapped properties"

        # Change mapping here

        # Define your mapping here for correlatedaccount data to compare
        $correlatedReferenceObject = [PSCustomObject]@{
            fullname = $correlatedAccount.name.formatted
            division = $correlatedAccount.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
            userName = $correlatedAccount.userName
        }

        # Define your mapping here for fieldmapping data to compare
        $accountDifferenceObject = [PSCustomObject]@{
            fullname = $account.name.formatted
            division = $account.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
            userName = $account.userName
        }

        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedReferenceObject.PSObject.Properties)
            DifferenceObject = @($accountDifferenceObject.PSObject.Properties)
        }  
        $accountPropertiesChanged = Compare-Object @splatCompareProperties -PassThru
        $accountOldProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "<=" }
        $accountNewProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "=>" }

        if ($accountNewProperties) {
            $actionAccount = "Update"
            Write-Information "Account property(s) required to update: $($accountNewProperties.Name -join ', ')"
        }
        else {
            $actionAccount = "NoChanges"
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
        "Update" {
            #region Update account
            $actionMessage = "updating account"

            # Create custom object with old and new values (for logging)
            $accountChangedPropertiesObject = [PSCustomObject]@{
                OldValues = @{}
                NewValues = @{}
            }

            foreach ($accountOldProperty in ($accountOldProperties | Where-Object { $_.Name -in $accountNewProperties.Name })) {
                $accountChangedPropertiesObject.OldValues.$($accountOldProperty.Name) = $accountOldProperty.Value
            }

            foreach ($accountNewProperty in $accountNewProperties) {
                $accountChangedPropertiesObject.NewValues.$($accountNewProperty.Name) = $accountNewProperty.Value
            }

            # Change mapping here
            $correlatedAccount.name.formatted = $account.name.formatted

            if ($account.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.PSObject.Properties.Name -contains 'division') {
                $correlatedAccount.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division = $account.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
            }

            if ($account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.PSObject.Properties.Name -contains 'SsoAccountKey') {
                $correlatedAccount.'urn:ietf:params:scim:schemas:zivver:0.1:User' | Add-Member -MemberType NoteProperty -Name "SsoAccountKey" -Value $account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.SsoAccountKey -Force
            }

            if ($account.PSObject.Properties.Name -contains 'userName') {
                $correlatedAccount.userName = $account.userName
            }

            $putZivverSplatParams = @{
                Headers  = $headers
                Endpoint = "Users/$($actionContext.References.Account)"
                Method   = 'PUT'
                Body     = $correlatedAccount | ConvertTo-Json
            }

            Write-Verbose "SplatParams: $($putZivverSplatParams | ConvertTo-Json)"

            if (-Not($actionContext.DryRun -eq $true)) {
                $updatedAccount = Invoke-ZivverRestMethod @putZivverSplatParams

                $outputContext.AccountReference = $updatedAccount.id
                $outputData = $updatedAccount

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account with userName [$($updatedAccount.userName)] and AccountReference [$($outputContext.AccountReference)] updated. Old values: $($accountChangedPropertiesObject.oldValues | ConvertTo-Json). New values: $($accountChangedPropertiesObject.newValues | ConvertTo-Json)"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would update account with userName [$($correlatedAccount.userName)] and AccountReference [$($outputContext.AccountReference)]. Old values: $($accountChangedPropertiesObject.oldValues | ConvertTo-Json). New values: $($accountChangedPropertiesObject.newValues | ConvertTo-Json)"
            }

            break
        }

        "NoChanges" {
            #region No changes
            $actionMessage = "skipping updating account"

            $outputData = $correlatedAccount

            Write-Information "Account with userName [$($correlatedAccount.userName)] and AccountReference: [$($actionContext.References.Account)] not updated. Reason: No changes."
            #endregion No changes

            break
        }

        "MultipleFound" {
            #region Multiple accounts found
            $actionMessage = "updating account"

            # Throw terminal error
            throw "Multiple accounts found with AccountReference [$($actionContext.References.Account)]. Please correct this so the persons are unique."
            #endregion Multiple accounts found

            break
        }

        "NotFound" {
            #region No account found
            $actionMessage = "updating account"
        
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
            id            = $outputData.id
            active        = [string]$outputData.active # value is returned as boleaan
            fullname      = $outputData.name.formatted
            division      = $outputData.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
            ssoAccountKey = $account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.ssoAccountKey # ssoAccountKey is not returned by Zivver, account is mapped to make sure the same value is returned
            userName      = $outputData.userName
        }
        Write-Verbose "output data to HelloID: [$($outputDataObject | Convertto-json)]"
        $outputContext.Data = $outputDataObject

        # Define your mapping here for returning the correct previous data to HelloID
        $outputPreviousDataObject = [PSCustomObject]@{
            id            = $outputPreviousData.id
            active        = [string]$outputPreviousData.active # value is returned as boleaan
            fullname      = $outputPreviousData.name.formatted
            division      = $outputPreviousData.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
            ssoAccountKey = $account.'urn:ietf:params:scim:schemas:zivver:0.1:User'.ssoAccountKey # ssoAccountKey is not returned by Zivver, account is mapped to make sure the same value is returned
            userName      = $outputPreviousData.userName
        }
        Write-Verbose "output previous data to HelloID: [$($outputPreviousDataObject | Convertto-json)]"
        $outputContext.PreviousData = $outputPreviousDataObject
    }
}