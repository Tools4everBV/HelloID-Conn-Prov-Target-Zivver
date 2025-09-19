#####################################################
# HelloID-Conn-Prov-Target-Zivver-Import
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

try {
    Write-Information 'Starting target account import'

    # Set authentication headers
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.Token)")

    $splatParams = @{
        Uri         = "$($actionContext.Configuration.baseUrl)/api/scim/v2/Users"
        Headers     = $headers
        Method      = 'GET'
        ContentType = 'application/json; charset=utf-8'
    }

    $users = Invoke-RestMethod @splatParams
    $existingAccounts = $users.Resources

    Write-Information "Successfully queried [$($existingAccounts.count)] existing accounts"

    $existingAccounts  | Add-Member -MemberType NoteProperty -Name 'division' -Value $null
    $existingAccounts  | Add-Member -MemberType NoteProperty -Name 'fullname' -Value $null

    # Example how to filter out users that are deleted by HelloID (Reconciliation)
    # $existingAccounts = $existingAccounts | Where-Object { $_.name.formatted -notlike "*(Deleted by HelloID)" } 

    # Map the imported data to the account field mappings
    foreach ($account in $existingAccounts) {
        $enabled = $false
        # Convert archived to disabled
        if ($account.active) {
            $enabled = $true
        }

        # Make sure the DisplayName has a value
        if ([string]::IsNullOrEmpty($account.username)) {
            $account.username = $account.id
        }

        $account.division = $account.'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'.division
        $account.fullname = $account.name.formatted

        # Return the result
        Write-Output @{
            AccountReference = $account.id
            DisplayName      = $account.name.formatted
            UserName         = $account.username
            Enabled          = $enabled
            Data             = $account
        }
    }
    Write-Information 'Target account import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.ErrorDetails.Message)"
            Write-Error "Could not import account entitlements. Error: $($ex.ErrorDetails.Message)"
        }
        else {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            Write-Error "Could not import account entitlements. Error: $($ex.Exception.Message)"
        }
    }
    else {
        Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import account entitlements. Error: $($ex.Exception.Message)"
    }
}