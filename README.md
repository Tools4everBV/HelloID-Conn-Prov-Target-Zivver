# HelloID-Conn-Prov-Target-Zivver

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

| :warning: Warning |
|:---------------------------|
| Note that this connector is "a work in progress" and therefore not ready to use in your production environment. |

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
      - [Account validation based on `$account.userName`](#account-validation-based-on-accountusername)
      - [Correlation](#correlation)
      - [Account object properties](#account-object-properties)
      - [Account object and comparison](#account-object-and-comparison)
      - [Email aliases](#email-aliases)
      - [Updating a Zivver user account](#updating-a-zivver-user-account)
        - [Example - updating the `active` attribute](#example---updating-the-active-attribute)
        - [Example - updating the email aliases array attribute](#example---updating-the-email-aliases-array-attribute)
      - [Error handling](#error-handling)
        - [When the division could not be found](#when-the-division-could-not-be-found)
      - [Creation / correlation process](#creation--correlation-process)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Zivver_ is a _target_ connector. Zivver provides secure communication solutions, primarily focused on email and file transfer. It offers a platform designed to protect sensitive information, such as personal data or confidential business data, from unauthorized access and interception.

### SCIM based API

SCIM stands for _System for Cross-domain Identity Management_. It is an open standard protocol that simplifies management of user identities and related information across different systems and domains.

The HelloID connector uses the API endpoints listed in the table below.

| Endpoint | Description |
| -------- | ----------- |
| /users   | -           |
| /groups  | -           |

### Available lifecycle actions

The following lifecycle events are available:

| Event            | Description                                 | Notes |
| ---------------- | ------------------------------------------- | ----- |
| create.ps1       | Create (or update) and correlate an account | -     |
| update.ps1       | Update the account                          | -     |
| enable.ps1       | Enable the account                          | -     |
| disable.ps1      | Disable the account                         | -     |
| grant.ps1        | Grants a permission to the account          | Not tested in version `1.0.0` |
| revoke.ps1       | Revokes a permission from the account       | Not tested in version `1.0.0` |
| entitlements.ps1 | Retrieves all entitlements                  | Not tested in version `1.0.0` |

## Getting started

### Functional description

The purpose of this connector is to _manage user account provisioning_ within Zivver.

In addition, the connector manages:

- Email aliases
  > - Email aliases will only be added, __not__ removed
  > - Email aliases will be added based on the contracts that are in scope of a certain business rule.
  > - The `company` property on the contract will be set as the domain portion of the email alias.
- Permissions / _shared mailboxes_

>:exclamation:It's important to note that version `1.0.0` of the connector is build on a production environment. Therefore, it has not been thoroughly tested.<br>

>:exclamation: Permissions and the _grant/revoke_ lifecycle actions were not available during development. In version `1.0.0` this code is developed based on documentation rather then an actual implementation.

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                                 | Mandatory | Example |
| ------- | ------------------------------------------- | --------- | ------- |
| BaseUrl | The URL to the API                          | Yes       | _https://app.zivver.com_ |
| Token   | The bearer token to authenticate to the API | Yes       | _ |

### Remarks

#### Account validation based on `$account.userName`

The account validation in the create lifecycle action is based on a scim filter using `$account.userName`. In version `1.0.0` of the connector, `$account.userName` is mapped to `$p.Accounts.MicrosoftActiveDirectory.mail`.

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
- `urn:ietf:params:scim:schemas:zivver:0.1:User.aliases`
- `active`

>:exclamation: Properties not mentioned above, are not managed or handled by HelloID.

#### Account object and comparison

The account object within Zivver is a complex object. Which means that, it contains hash tables and arrays. A custom compare function is added in order to compare the Zivver account with the account object from HelloID. The full comparison logic consists of two functions. `Compare-ZivverAccountObject` and `Compare-Array`.

The `Compare-ZivverAccountObject` is tailored to compare __only__ what is managed.

#### Email aliases

In the HelloID connector, email aliases for Zivver accounts are extracted from a person contract and added to the user's Zivver account.

The email aliases are dynamically generated based on the company property found in the person contract. This ensures that each user's email alias is unique and corresponds to their respective organization.

>:exclamation: It's important to note that email aliases are only added, not removed, from the Zivver account.

#### Updating a Zivver user account

Zivver only supports the `HTTP.PUT` method for updating user accounts, requiring the entire user object to be included in each call. However, a partial `PUT` is also supported. In version `1.0.0` of the connector, a partial `PUT` is implemented, allowing updates to specific parts of the user object.

##### Example - updating the `active` attribute

```json
{
    "schemas": [
        "urn:ietf:params:scim:schemas:core:2.0:User",
        "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User",
        "urn:ietf:params:scim:schemas:zivver:0.1:User"
    ],
    "active": "false"
}
```

##### Example - updating the email aliases array attribute

```json
{
    "schemas": [
        "urn:ietf:params:scim:schemas:core:2.0:User",
        "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User",
        "urn:ietf:params:scim:schemas:zivver:0.1:User"
    ],
    "urn:ietf:params:scim:schemas:zivver:0.1:User:aliases": {
        "aliases": [
            "j.doe@example",
            "j.doe@anotherExample"
        ]
    }
}
```

#### Error handling

##### When the division could not be found

The account object in the `create` lifecycle action contains a property called `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division`. In version `1.0.0` of the connector, this value is set to `p.PrimaryContract.Department.DisplayName`. If the department can't be found within Zivver, an error will be thrown (By Zivver). _Error: Invalid division: {name of division}_. As a result, the create lifecycle action will fail.

#### Creation / correlation process

A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior in the ``configuration`` by setting the checkbox ``UpdatePersonOnCorrelate`` to the value of ``true``.

>:exclamation:Be aware that this might have unexpected implications.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
