# HelloID-Conn-Prov-Target-Zivver

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center"> 
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Zivver/blob/main/Logo.png?raw=true">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Zivver](#helloid-conn-prov-target-zivver)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
    - [SCIM based API](#scim-based-api)
  - [Getting started](#getting-started)
    - [Functional description](#functional-description)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Remarks](#remarks)
      - [Concurrent actions](#concurrent-actions)
      - [SsoAccountKey](#ssoaccountkey)
      - [Updating a Zivver user account](#updating-a-zivver-user-account)
      - [Error handling](#error-handling)
        - [When the division could not be found](#when-the-division-could-not-be-found)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction
Supported features:
| Feature                             | Supported | Actions                                                  | Remarks |
| ----------------------------------- | --------- | -------------------------------------------------------- | ------- |
| **Account Lifecycle**               | ✅         | Create, Update, Enable, Disable, Delete (also a disable) |         |
| **Permissions**                     | ✅         | Retrieve, Grant, Revoke groups                           |         |
| **Resources**                       | ❌         | -                                                        |         |
| **Entitlement Import: Accounts**    | ✅         | -                                                        |         |
| **Entitlement Import: Permissions** | ❌         | -                                                        |         |
| **Governance Reconciliation Resolutions** | ✅        | Delete                                                        | Delete is treated as a disable action with the option to update values. Please adjust the configuration accordingly in the delete script |

_HelloID-Conn-Prov-Target-Zivver_ is a _target_ connector. Zivver provides secure communication solutions, primarily focused on email and file transfer. It offers a platform designed to protect sensitive information, such as personal data or confidential business data, from unauthorized access and interception.

### SCIM based API

SCIM stands for _System for Cross-domain Identity Management_. It is an open standard protocol that simplifies the management of user identities and related information across different systems and domains.

The HelloID connector uses the API endpoints listed in the table below.

| Endpoint | Description                                                           |
| -------- | --------------------------------------------------------------------- |
| /users   | `GET / POST / PATCH` actions to read and write the user in Zivver     |
| /groups  | `GET / PATCH` actions to read and write functional accounts in Zivver |

> [!TIP]
> _For more information on the Zivver API, please refer to the [Zivver website](https://docs.zivver.com/en/admin/integrations/scim-v2.html)_.

## Getting started

### Functional description

The purpose of this connector is to _manage user account provisioning_ within Zivver.

In addition, the connector manages:

- Permissions / Named in Zivver: functional accounts

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                                 | Mandatory | Example                  |
| ------- | ------------------------------------------- | --------- | ------------------------ |
| BaseUrl | The URL to the API                          | Yes       | _https://app.zivver.com_ |
| Token   | The bearer token to authenticate to the API | Yes       | _                        |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Zivver_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

 | Setting                   | Value      |
 | ------------------------- | ---------- |
 | Enable correlation        | `True`     |
 | Person correlation field  | ``         |
 | Account correlation field | `userName` |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the [_fieldMapping.json_](./fieldMapping.json) file.

> [!NOTE]
> Mapping a `SCIM` property like `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division` is not possible in the field mapping. For this reason, the field mapping is mapped in the Powershell account lifecycle scripts. When adding additional fields please keep in mind you have to enrich the mapping in the PowerShell scripts. Search for `Change mapping here` for all the mapping locations in the Powershell account lifecycle scripts.

### Remarks

#### Concurrent actions

> [!IMPORTANT]
> Granting and revoking groups is done by editing members after receiving the group members. For this reason, the concurrent actions need to be set to `1`.

When HelloID sends too many requests it is possible to receive the error below.

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
To use Single Sign On in Zivver the `SsoAccountKey` needs to be filled. In our experience implementing this, we learned that we needed to add the `SsoAccountKey` to every `PUT` call on the `user` to Zivver. This value is not returned by Zivver when using the `GET` call.

> [!IMPORTANT]
> Because Zivver doesn't return `SsoAccountKey` in the `GET` call. The connector doesn't know when to update this value. The connector now only updates this field when another value requires an update. Please keep this in mind while implementing this connector. 

The HelloID connector is designed to manage the following properties of the user object:

- `name.formatted`
- `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division`
- `urn:ietf:params:scim:schemas:zivver:0.1:User.SsoAccountKey`
- `active`
- `userName`

>:exclamation: Properties not mentioned above, are not managed or handled by HelloID.

#### Updating a Zivver user account

Zivver only supports the `HTTP.PUT` method for updating user accounts, requiring the entire user object to be included in each call. If a partial `PUT` is used without the SsoAccountKey the SSO in Zivver will break.

The Zivver user response is used and enriched with the necessary updates. This is how we ensure the entire user `GET` response is included in each `PUT` call.

#### Error handling

##### When the division could not be found

The field mapping object `division` is mapped to a property called `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division`. If the division can't be found within Zivver, an error will be thrown (By Zivver). _Error: Invalid division: {name of division}_. As a result, the create/update lifecycle action will fail.

> [!TIP]
> If you're not using division, map this field to the fixed value '/'. This is how Zivver returns an empty division so the Compare-Object keeps working in the script.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/4865-helloid-conn-prov-target-zivver)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/