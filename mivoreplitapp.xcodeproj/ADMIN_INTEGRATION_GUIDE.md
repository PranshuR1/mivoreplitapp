# Quick Integration Guide

## How to Add Admin Access to Your App

### Option 1: Add to Settings (Recommended)

Add this section to your `SettingsView.swift`, right after the "Advanced" section and before "Danger Zone":

```swift
// In SettingsView.swift, add this state variable at the top:
@State private var showAdminAccess = false

// Add this new section in the body, after "Advanced" section:
settingsSection("System") {
    settingsActionRow(
        icon: "shield.checkered", 
        title: "Admin Access", 
        subtitle: "Manage users and view system statistics"
    ) {
        showAdminAccess = true
    }
}

// Add this sheet modifier at the end of the ZStack or main view:
.sheet(isPresented: $showAdminAccess) {
    AdminAccessView()
        .environmentObject(appVM)
}
```

### Option 2: Hidden Gesture Access (More Secure)

Add a secret gesture to access admin features anywhere in your app:

```swift
// In any view (e.g., SettingsView or main dashboard)
@State private var tapCount = 0
@State private var showAdminAccess = false

// Add this modifier to your view:
.onTapGesture {
    tapCount += 1
    if tapCount >= 7 {
        showAdminAccess = true
        tapCount = 0
    }
    // Reset tap count after 2 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        tapCount = 0
    }
}
.sheet(isPresented: $showAdminAccess) {
    AdminAccessView()
        .environmentObject(appVM)
}
```

### Option 3: Direct Navigation Link

Add a navigation link in your settings or debug menu:

```swift
NavigationLink {
    AdminAccessView()
        .environmentObject(appVM)
} label: {
    HStack(spacing: 12) {
        Image(systemName: "shield.checkered")
            .foregroundColor(MivoColors.accent)
        VStack(alignment: .leading, spacing: 2) {
            Text("Admin Panel")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MivoColors.textPrimary)
            Text("System administration")
                .font(.system(size: 12))
                .foregroundColor(MivoColors.textMuted)
        }
        Spacer()
    }
    .padding()
}
```

## First-Time Setup Steps

1. **Add Admin Access**: Choose one of the options above and add it to your app
2. **Run Your App**: Build and run your app
3. **Access Admin**: Navigate to where you added the admin access
4. **Initialize Account**: 
   - First time you access it, you'll see "Initialize Admin Account"
   - Tap the button to create the admin account with credentials:
     - Email: `useparkez@gmail.com`
     - Password: `Pranshu@123`
5. **Login**: After initialization, you can login with those credentials
6. **Manage Users**: You're now in the admin dashboard!

## Example: Full SettingsView Integration

Here's a complete example of adding admin access to your Settings:

```swift
// Add to SettingsView state variables
@State private var showAdminAccess = false

// In the body, add a new section:
settingsSection("System Administration") {
    Button {
        showAdminAccess = true
    } label: {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 20))
                .foregroundColor(MivoColors.accent)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Admin Dashboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MivoColors.textPrimary)
                Text("Manage users and view statistics")
                    .font(.system(size: 12))
                    .foregroundColor(MivoColors.textMuted)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundColor(MivoColors.textMuted)
        }
        .padding(15)
    }
    .buttonStyle(.plain)
}

// Add sheet at the bottom of your view hierarchy
.sheet(isPresented: $showAdminAccess) {
    AdminAccessView()
        .environmentObject(appVM)
}
```

## Testing the Admin System

### Test User Management

1. Create a test user account in your app
2. Login as admin
3. View the test user in the admin dashboard
4. Click on the user to see details
5. Try deleting the user

### Test Search

1. Create multiple users with different names/emails
2. Login as admin
3. Use the search bar to filter users

### Test Statistics

1. Create users and have them create sessions
2. Login as admin
3. View aggregate statistics at the top of the dashboard

## Production Considerations

### Security
- Change the default admin password before shipping to production
- Consider adding 2FA or additional authentication layers
- Limit admin access to specific build configurations or environments

### Hidden Access (Recommended for Production)
Instead of a visible button, use a hidden gesture:

```swift
// In SettingsView header
.onLongPressGesture(minimumDuration: 3.0) {
    showAdminAccess = true
}
```

Or require multiple taps on a specific UI element:

```swift
Text("Mivo · Data stays on your device")
    .font(.system(size: 12))
    .foregroundColor(MivoColors.textMuted)
    .onTapGesture(count: 5) {
        showAdminAccess = true
    }
```

### Debug-Only Access
Only show admin in debug builds:

```swift
#if DEBUG
settingsSection("Developer") {
    settingsActionRow(icon: "shield.checkered", title: "Admin Access", subtitle: "Development only") {
        showAdminAccess = true
    }
}
#endif
```

## Troubleshooting

### "Admin Already Exists" Error
- The admin account was already created
- You need to login instead of setup
- To reset: Delete the app and reinstall, or use keychain access to remove admin credentials

### Can't See Any Users
- Make sure you have users in the app
- Check that you're logged in as admin
- Verify user data exists in storage

### Colors Not Showing Correctly
- Ensure `MivoColorsExtension.swift` is in your project
- Check that it's included in your app target
- Import SwiftUI in all admin view files

---

Need help? Check the full `ADMIN_README.md` for detailed documentation.
