# HelloID-Conn-Prov-Target-Zivver

| :information_source: Information                                                                                                                                                                                                                                                                                                                                                          |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center"> 
  <img src="https://www.zivver.com/hs-fs/hubfs/ZIVVER_WORDMARK_K.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Zivver](#helloid-conn-prov-target-zivver)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
    - [SCIM based API](#scim-based-api)
    - [Available lifecycle actions](#available-lifecycle-actions)
  - [Getting started](#getting-started)
    - [Functional description](#functional-description)
    - [Connection settings](#connection-settings)
    - [Remarks](#remarks)
      - [Concurrent actions](#concurrent-actions)
      - [SsoAccountKey](#ssoaccountkey)
      - [Account validation based on `$account.userName`](#account-validation-based-on-accountusername)
      - [Correlation](#correlation)
      - [Account object properties](#account-object-properties)
      - [Account object and comparison](#account-object-and-comparison)
      - [Updating a Zivver user account](#updating-a-zivver-user-account)
      - [Error handling](#error-handling)
        - [When the division could not be found](#when-the-division-could-not-be-found)
      - [Creation / correlation process](#creation--correlation-process)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Zivver_ is a _target_ connector. Zivver provides secure communication solutions, primarily focused on email and file transfer. It offers a platform designed to protect sensitive information, such as personal data or confidential business data, from unauthorized access and interception.

### SCIM based API

SCIM stands for _System for Cross-domain Identity Management_. It is an open standard protocol that simplifies the management of user identities and related information across different systems and domains.

The HelloID connector uses the API endpoints listed in the table below.

| Endpoint | Description                                             |
| -------- | ------------------------------------------------------- |
| /users   | -                                                       |
| /groups  | Named in Zivver: functional accounts (shared mailboxes) |

### Available lifecycle actions

The following lifecycle events are available:

| :information_source: Information                                                                |
| :---------------------------------------------------------------------------------------------- |
| The enable is handled in the create.ps1 script. The disable is handled in the delete.ps1 script |

| Event            | Description                                                           |
| ---------------- | --------------------------------------------------------------------- |
| create.ps1       | Create (or update) and correlate an account. Also, enable the account |
| update.ps1       | Update the account                                                    |
| delete.ps1       | Only disables the account. Deleting an account is not supported       |
| grant.ps1        | Grants permission to the account                                      |
| revoke.ps1       | Revokes permission from the account                                   |
| entitlements.ps1 | Retrieves all entitlements                                            |

## Getting started

### Functional description

The purpose of this connector is to _manage user account provisioning_ within Zivver.

In addition, the connector manages:

- Permissions / _shared mailboxes_

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                                 | Mandatory | Example                  |
| ------- | ------------------------------------------- | --------- | ------------------------ |
| BaseUrl | The URL to the API                          | Yes       | _https://app.zivver.com_ |
| Token   | The bearer token to authenticate to the API | Yes       | _                        |

### Remarks

#### Concurrent actions
| :warning: Warning                                                                                                                                         |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Granting and revoking groups is done by editing members after receiving the group members. For this reason, the concurrent actions need to be set to `1`. |

When not used it is possible to get the error below.

```json
Error:
{
  "code": 429,
  "message": "Too Many Requests",
  "emptiedBucketDetails": {
    "limiterId": "cab",
    "budget": 50,
    "windowSeconds": 10
  },
  "reference": "https://tools.ietf.org/html/draft-polli-ratelimit-headers-02"
}
```

#### SsoAccountKey
| :warning: Warning                                                                               |
| :-----------------------------------------------------------------------------------------------|
| This connector in combination with SSO is only implemented with a Google Workspace environment. |

To use Single Sign On in Zivver the `SsoAccountKey` needs to be filled. In our experience implementing this, we learned that we needed to add the `SsoAccountKey` to every `PUT` call on the `user` to Zivver. This value is not returned by Zivver when using the `GET` call.
Please keep this in mind when editing scripts and testing.

#### Account validation based on `$account.userName`

The account validation in the create lifecycle action is based on a scim filter using `$account.userName`. In version `1.1.0` of the connector, `$account.userName` is mapped to `$p.Accounts.MicrosoftActiveDirectory.UserPrincipalName`.

The filter is used as follows:

```powershell
$response = Invoke-RestMethod -Uri "$($config.BaseUrl)/api/scim/v2/Users?filter=userName eq `"user@domain.nl`""
```
> Other lifecycle actions use the `$aRef` in order to search for users within Zivver.

#### Correlation

The account correlation is based on the `id` of the user entity within Zivver.

#### Account object properties

Currently, a Zivver account object contains the following properties:

```json
{
  "id": "ea7f1807-5cc2-4aea-b6c3-57ad0a01443d",
  "name": {
    "formatted": "Dave Graaf"
  },
  "meta": {
    "created": "2021-03-16",
    "location": "/scim/v2/Users/ea7f1807-5cc2-4aea-b6c3-57ad0a01443d",
    "resourceType": "User"
  },
  "phoneNumbers": [],
  "schemas": [
    "urn:ietf:params:scim:schemas:core:2.0:User",
    "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User",
    "urn:ietf:params:scim:schemas:zivver:0.1:User"
  ],
  "userName": "d.graaf@example",
  "active": true,
  "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User": {
    "division": "Development"
  },
  "urn:ietf:params:scim:schemas:zivver:0.1:User": {
    "aliases": [
      "d.graaf@example"
    ],
    "delegates": [
      "c.brink@example",
    ]
  }
}
```

The HelloID connector is designed to manage the following properties of the user object:

- `name.formatted`
- `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division`
- `urn:ietf:params:scim:schemas:zivver:0.1:User.SsoAccountKey`
- `active`
- `userName`

>:exclamation: Properties not mentioned above, are not managed or handled by HelloID.

#### Account object and comparison

The account object within Zivver is a complex object. Which means that it contains hash tables and arrays. A custom compare function is added in order to compare the Zivver account with the account object from HelloID. The full comparison logic consists of two functions. `Compare-ZivverAccountObject` and `Compare-Array`.

The `Compare-ZivverAccountObject` is tailored to compare __only__ what is managed and is only used in the update script.

#### Updating a Zivver user account

Zivver only supports the `HTTP.PUT` method for updating user accounts, requiring the entire user object to be included in each call. If a partial `PUT` is used without the SsoAccountKey the SSO in Zivver will break.

The Zivver user response is used and enriched with the necessary updates. This is how we ensure the entire user `GET` response is included in each `PUT` call.

#### Error handling

##### When the division could not be found

The account object in the `create` lifecycle action contains a property called `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division`. In version `1.1.0` of the connector, this value is set to `p.PrimaryContract.Department.DisplayName`. If the department can't be found within Zivver, an error will be thrown (By Zivver). _Error: Invalid division: {name of division}_. As a result, the create lifecycle action will fail.

#### Creation / correlation process

It is possible to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior in the ``configuration`` by setting the checkbox ``UpdatePersonOnCorrelate`` to the value of ``true``.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/4865-helloid-conn-prov-target-zivver)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
