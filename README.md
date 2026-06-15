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
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Concurrent actions](#concurrent-actions)
    - [SsoAccountKey](#ssoaccountkey)
    - [Updating a Zivver user account](#updating-a-zivver-user-account)
    - [Error handling](#error-handling)
      - [When the division could not be found](#when-the-division-could-not-be-found)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction
_HelloID-Conn-Prov-Target-Zivver_ is a _target_ connector. _Zivver_ provides secure communication solutions, primarily focused on email and file transfer. It offers a platform designed to protect sensitive information, such as personal data or confidential business data, from unauthorized access and interception.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks                                             |
| ----------------------------------------- | --------- | --------------------------------------- | --------------------------------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete | Delete performs a disable action                    |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke                 | Permissions are Zivver functional accounts (groups) |
| **Resources**                             | ❌         | -                                       |                                                     |
| **Entitlement Import: Accounts**          | ✅         | -                                       |                                                     |
| **Entitlement Import: Permissions**       | ✅         | -                                       |                                                     |
| **Governance Reconciliation Resolutions** | ✅         | -                                       |                                                     |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```text
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Zivver/refs/heads/main/Icon.png
```

### Requirements

- A valid Zivver SCIM bearer token.
- API access to the Zivver tenant (for example, `https://app.zivver.com`).
- Concurrent actions in HelloID must be set to `1` for safe permission changes.

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                                 | Mandatory | Example                  |
| ------- | ------------------------------------------- | --------- | ------------------------ |
| BaseUrl | The URL to the API                          | Yes       | `https://app.zivver.com` |
| Token   | The bearer token to authenticate to the API | Yes       |                          |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Zivver_ to a person in _HelloID_.

| Setting                   | Value                       |
| ------------------------- | --------------------------- |
| Enable correlation        | `True`                      |
| Person correlation field  | `Account.UserPrincipalName` |
| Account correlation field | `userName`                  |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the [_fieldMapping.json_](./fieldMapping.json) file.

> [!NOTE]
> Mapping a `SCIM` property like `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division` is not possible in the field mapping. For this reason, the field mapping is mapped in the PowerShell account lifecycle scripts. When adding additional fields, enrich the mapping in the PowerShell scripts. Search for `Change mapping here` for all mapping locations.

### Account Reference

The account reference is populated with the property `id` from _Zivver_.

## Remarks

### Concurrent actions

> [!IMPORTANT]
> Granting and revoking groups is done by editing members after receiving the current group members. For this reason, concurrent actions need to be set to `1`.

When HelloID sends too many requests, the API can respond with:

```json
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

### SsoAccountKey

To use Single Sign On in Zivver, `SsoAccountKey` must be populated. This value is not returned by Zivver in `GET` responses.

> [!IMPORTANT]
> Because Zivver does not return `SsoAccountKey` in the `GET` response, the connector cannot detect standalone SsoAccountKey changes. It updates this field when another managed value requires an update.

The HelloID connector manages the following user properties:

- `name.formatted`
- `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division`
- `urn:ietf:params:scim:schemas:zivver:0.1:User.SsoAccountKey`
- `active`
- `userName`

Properties not listed above are not managed by HelloID.

### Updating a Zivver user account

Zivver only supports `HTTP.PUT` for updating user accounts, requiring the full user object in each call. A partial `PUT` without `SsoAccountKey` can break SSO.

The connector enriches the Zivver `GET` response with required changes and sends that full payload in each `PUT` request.

### Error handling

#### When the division could not be found

The field mapping object `division` is mapped to `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division`. If the division cannot be found in Zivver, Zivver throws an error, for example: _Invalid division: {name of division}_. As a result, create and update lifecycle actions fail.

> [!TIP]
> If division is not used, map this field to the fixed value `/`. Zivver returns `/` as an empty division value, which keeps `Compare-Object` behavior stable in the script.

## Development resources

### API endpoints

The following endpoints are used by the connector.

| Endpoint | HTTP Method    | Description                                              |
| -------- | -------------- | -------------------------------------------------------- |
| /users   | GET, POST, PUT | Retrieve, create, and update users                       |
| /groups  | GET, PATCH     | Retrieve groups and manage functional account membership |

### API documentation

- https://docs.zivver.com/en/admin/integrations/scim-v2.html

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/