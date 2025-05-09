#################################################
# HelloID-Conn-Prov-Target-Zivver-Permissions-Groups-Import
# Correlate to permission
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
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
    # Set authentication headers
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.Token)")

    $zivverGroups = @()

    $actionMessage = "querying Zivver groups"
   
	$getZivverSplatParams = @{
		Uri         = "$($actionContext.Configuration.BaseUrl)/api/scim/v2/Groups"
		Headers     = $headers
		ContentType = 'application/json'
        Method   = 'GET'
    }
    $zivverGroups = (Invoke-RestMethod @getZivverSplatParams).resources
        
    Write-Information "Successfully queried [$($zivverGroups.count)] existing Zivver groups"

    $actionMessage = "querying Zivver Group Members"
    foreach ($zivverGroup in $zivverGroups) {          
    
        $zivverGroupMembers = $zivverGroup.members
        $numberOfAccounts = $(($zivverGroupMembers | Measure-Object).Count)   

        # Make sure the displayname has a value of max 100 char
        if (-not([string]::IsNullOrEmpty($zivverGroup.displayName))) {
            $displayname = $($zivverGroup.displayName).substring(0, [System.Math]::Min(100, $($zivverGroup.displayName).Length))
        }
        else {
            $displayname = $zivverGroup.id
        }
        
        $permission = @{
            PermissionReference = @{
                Reference = $zivverGroup.id
            }       
            DisplayName         = $displayName
        }

        # Batch permissions based on the amount of account references, 
        # to make sure the output objects are not above the limit
        $accountsBatchSize = 500
        if ($numberOfAccounts -gt 0) {
            $accountsBatchSize = 500
            $batches = 0..($numberOfAccounts - 1) | Group-Object { [math]::Floor($_ / $accountsBatchSize ) }
            foreach ($batch in $batches) {
                $permission.AccountReferences = [array]($batch.Group | ForEach-Object { @($zivverGroupMembers[$_].value) })
                Write-Output $permission
            }
        }
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-ZivverError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
}