# Admin Account System - Mivo

## Overview

This admin system provides a secure administrative interface for managing all users in the Mivo app. The admin can view user statistics, delete users, and monitor usage across the entire app.

## Admin Credentials

**Email:** `useparkez@gmail.com`  
**Password:** `Pranshu@123`

## Features

### 1. **Admin Dashboard**
- View all registered users
- See aggregate statistics (total users, sessions, minutes)
- Search users by email or name
- Quick access to user actions via context menu

### 2. **User Management**
- View detailed user information
- Delete user accounts
- View user's sessions and truth checks
- See onboarding profiles

### 3. **Security**
- Passwords are hashed using SHA-256 with 120,000 iterations
- Admin session management
- Separate keychain storage for admin credentials
- Constant-time password comparison to prevent timing attacks

## Setup Instructions

### First-Time Setup

1. **Initialize Admin Account**
   
   Add the `AdminAccessView` to your app (suggested: in Settings or as a hidden gesture):
   
   ```swift
   // In your SettingsView or main navigation
   NavigationLink {
       AdminAccessView()
           .environmentObject(appVM)
   } label: {
       Text("Admin Access")
   }
   ```

2. **Alternative: Add a Secret Gesture**
   
   You can add a hidden tap gesture to access admin features:
   
   ```swift
   // In your main view
   .onTapGesture(count: 5) {
       showAdminAccess = true
   }
   .sheet(isPresented: $showAdminAccess) {
       AdminAccessView()
           .environmentObject(appVM)
   }
   ```

3. **Run Admin Setup**
   
   When you first access `AdminAccessView`, it will detect that no admin account exists and show the setup screen. Tap "Create Admin Account" to initialize the account with the specified credentials.

### Logging In as Admin

1. Access the admin login screen through `AdminAccessView`
2. Enter the admin credentials:
   - Email: `useparkez@gmail.com`
   - Password: `Pranshu@123`
3. Tap "Login as Admin"
4. You'll be taken to the Admin Dashboard

## File Structure

```
Admin System Files:
├── AdminModels.swift           # Data models for admin and user info
├── AdminService.swift          # Service layer for admin operations
├── AdminDashboardView.swift    # Main dashboard UI
├── AdminLoginView.swift        # Login screen
├── AdminSetupView.swift        # First-time setup screen
├── AdminAccessView.swift       # Entry point for admin features
├── MivoColorsExtension.swift   # Additional colors for admin UI
└── ADMIN_README.md            # This file
```

## Usage Examples

### Viewing All Users

```swift
// From within AdminDashboardView, users are loaded automatically
let users = try AdminService.getAllUsers()
```

### Deleting a User

```swift
// Delete by email
try AdminService.deleteUser(email: "user@example.com")
```

### Getting User Details

```swift
// Get full user information with sessions and truth checks
let (user, sessions, truthChecks) = try AdminService.getUserDetails(email: "user@example.com")
```

### Checking Admin Authentication

```swift
if AdminService.isAdminAuthenticated() {
    // Admin is logged in
    // Show admin features
} else {
    // Require login
}
```

### Logging Out Admin

```swift
AdminService.logoutAdmin()
```

## Admin Dashboard Features

### Statistics Overview
- **Total Users**: Count of all registered users
- **Total Sessions**: Sum of all user sessions
- **Total Minutes**: Total screen time across all users

### User List
Each user card shows:
- Name and email
- Session count
- Total minutes
- Truth check count
- Last session date
- Account creation date

### User Actions
- **View Details**: See comprehensive user information
- **Delete User**: Remove user account and all associated data

### Search
- Search users by email or name
- Real-time filtering

## User Details View

When viewing a specific user, you can see:

1. **User Information**
   - Name, email, creation date
   - Last session date

2. **Statistics**
   - Total sessions
   - Total time spent
   - Truth checks completed
   - Average session length

3. **Onboarding Profile**
   - Primary intention
   - Scroll time estimate
   - Preferred apps
   - Age information

4. **Recent Sessions** (up to 5 most recent)
   - Intention
   - Date
   - Actual vs planned duration

5. **Truth Checks** (up to 5 most recent)
   - Date
   - Guess vs actual comparison
   - Accuracy percentage

## Security Considerations

### Password Storage
- Admin passwords are hashed using SHA-256 with 120,000 iterations
- Passwords are never stored in plain text
- Uses CryptoKit for cryptographic operations
- Stored securely in iOS Keychain

### Session Management
- Admin sessions are tracked separately from user sessions
- Sessions can be invalidated
- Automatic logout available

### Authorization
- All admin operations check authentication first
- Throws `AdminError.notAuthorized` if not authenticated
- Constant-time password comparison prevents timing attacks

## Customization

### Changing Admin Credentials

To change the default admin credentials:

1. Delete the existing admin account from keychain
2. Update credentials in `AdminSetupView.swift`:
   ```swift
   private let adminEmail = "new-email@example.com"
   private let adminPassword = "NewPassword123"
   ```
3. Re-run the setup process

### Styling

All admin views use the existing `MivoColors` palette for consistency. To customize:

- Edit colors in `MivoColorsExtension.swift`
- Modify view layouts in the respective view files

### Adding More Admin Features

To add new admin capabilities:

1. Add new functions to `AdminService`
2. Create new views or extend existing ones
3. Add navigation in `AdminDashboardView`

## API Reference

### AdminService

#### Initialization
```swift
// Initialize admin account (one-time setup)
static func initializeAdmin(email: String, password: String) throws
```

#### Authentication
```swift
// Login with credentials
static func loginAdmin(email: String, password: String) throws -> Bool

// Check if admin is logged in
static func isAdminAuthenticated() -> Bool

// Logout admin
static func logoutAdmin()

// Check if admin exists
static func adminExists() -> Bool
```

#### User Management
```swift
// Get all users
static func getAllUsers() throws -> [UserAccountInfo]

// Delete a user
static func deleteUser(email: String) throws

// Get user details
static func getUserDetails(email: String) throws -> (user: UserAccountInfo, sessions: [Session], truthChecks: [TruthCheckGuess])
```

### AdminError

```swift
enum AdminError: LocalizedError {
    case notAuthorized
    case invalidCredentials
    case alreadyInitialized
    case notInitialized
}
```

## Troubleshooting

### Admin Account Won't Initialize
- Check that the admin doesn't already exist
- Verify keychain access permissions
- Check console for error messages

### Can't Delete Users
- Ensure admin is authenticated
- Verify user email is correct
- Check that the user exists in storage

### Colors Not Showing
- Ensure `MivoColorsExtension.swift` is included in your target
- Check that base `MivoColors` is properly defined
- Verify imports in view files

### Session Lost
- Admin sessions are stored in UserDefaults
- Clearing app data will log out admin
- Re-login to restore access

## Best Practices

1. **Secure Credentials**: Change default credentials in production
2. **Backup Data**: Export user data before bulk deletions
3. **Monitor Usage**: Regularly check statistics for unusual patterns
4. **Test Locally**: Test all admin operations in a development environment first
5. **Access Control**: Consider adding additional authentication layers for production

## Future Enhancements

Potential additions to the admin system:

- [ ] Export all user data to CSV/JSON
- [ ] Bulk user operations
- [ ] User activity graphs and charts
- [ ] Email notifications for admin actions
- [ ] Audit log of admin actions
- [ ] Multi-admin support with different permission levels
- [ ] Remote admin API
- [ ] Advanced search and filtering
- [ ] User engagement analytics

## Support

For issues or questions about the admin system, please review:
1. This README
2. Source code comments
3. Error messages in console
4. `ARCHITECTURE.md` for overall app structure

---

**Version:** 1.0  
**Last Updated:** May 2026  
**Author:** Mivo Development Team
