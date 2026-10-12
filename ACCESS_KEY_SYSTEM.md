# Access Key System Documentation

## Overview

The access key system allows users to unlock modpacks by entering valid access keys. The system validates keys against an API endpoint and stores successful validations in SharedPreferences.

## Components

### 1. AccessKeyService (`lib/helpers/access_key_service.dart`)

The main service class that handles all access key operations.

#### Key Methods:

- `validateAccessKey(String accessKey)` - Validates a key against the API and returns modpack info
- `saveAccessKey(String accessKey)` - Validates and saves a key, returns modpack info if successful
- `removeAccessKey(String accessKey, String modpackId)` - Removes a key and disables modpack
- `getAccessKeys()` - Retrieves all stored access keys
- `getEnabledModpacks()` - Retrieves all enabled modpacks
- `isModpackEnabled(String modpackId)` - Checks if a specific modpack is enabled

### 2. Settings Page Integration

The settings page now includes an "Access Keys" section where users can:

- Enter new access keys (modpack info is retrieved from API response)
- View their active access keys
- View enabled modpacks
- Remove access keys (which also disables the modpack)

### 3. ModpackAccessHelper (`lib/helpers/modpack_access_helper.dart`)

Utility class with helper methods for checking modpack access throughout your app.

## Configuration

### API Endpoint

Update the `_baseUrl` constant in `AccessKeyService`:

```dart
static const String _baseUrl = 'https://your-api-endpoint.com/validate-key';
```

The service makes a GET request to: `{_baseUrl}?key={accessKey}`

Your API should return:
- **Status 200**: Key is valid, with JSON response containing modpack information
- **Any other status**: Key is invalid

Expected JSON response format:
```json
{
  "id": "premium_modpack_1",
  "name": "Premium Modpack",
  "version": "1.0.0",
  "description": "A premium modpack with exclusive content"
}
```

## Usage Examples

### In Settings Page
Users can add access keys through the UI. The system will:
1. Validate the key against your API
2. If valid, extract modpack info from API response
3. Store the key and enable the associated modpack
4. Show success message with modpack name

### In Your App Code

```dart
// Check if user can access a modpack
bool canAccess = await AccessKeyService.isModpackEnabled('premium_modpack_1');

if (canAccess) {
  // Show the modpack
} else {
  // Show "Access Denied" or redirect to purchase page
}

// Get all accessible modpacks
List<String> accessibleModpacks = await ModpackAccessHelper.getUserAccessibleModpacks();

// Filter a list of modpacks
List<String> allModpacks = ['free_pack', 'premium_pack_1', 'premium_pack_2'];
List<String> userModpacks = await ModpackAccessHelper.filterAccessibleModpacks(allModpacks);
```

## Data Storage

The system uses SharedPreferences to store:

- `accessKeys`: List of validated access keys
- `enabledModpacks`: List of modpack IDs that the user has access to

## Security Considerations

1. **API Security**: Ensure your validation API is secure and rate-limited
2. **Key Format**: Consider using cryptographically secure key formats
3. **Local Storage**: Keys are stored locally - consider encryption for sensitive applications
4. **Network Security**: Use HTTPS for API calls

## Error Handling

The system handles various error scenarios:

- Network failures during validation
- Invalid API responses
- Malformed access keys
- Storage errors

Errors are logged to console and appropriate user feedback is provided through SnackBars.

## Future Enhancements

Consider adding:

- Key expiration dates
- Usage tracking/analytics
- Bulk key operations
- Key categories/types
- Offline validation for limited periods