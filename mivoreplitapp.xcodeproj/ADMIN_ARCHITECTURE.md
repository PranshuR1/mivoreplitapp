# Admin System Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐  │
│  │   Settings   │─────▶│ AdminAccess  │─────▶│ AdminSetup   │  │
│  │     View     │      │     View     │      │     View     │  │
│  └──────────────┘      └──────────────┘      └──────────────┘  │
│                               │                                 │
│                               ▼                                 │
│                        ┌──────────────┐                         │
│                        │  AdminLogin  │                         │
│                        │     View     │                         │
│                        └──────────────┘                         │
│                               │                                 │
│                               ▼                                 │
│                        ┌──────────────┐                         │
│                        │    Admin     │                         │
│                        │  Dashboard   │                         │
│                        └──────────────┘                         │
│                               │                                 │
│                               ▼                                 │
│                        ┌──────────────┐                         │
│                        │ UserDetails  │                         │
│                        │     View     │                         │
│                        └──────────────┘                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                       BUSINESS LOGIC                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                     ┌──────────────────┐                        │
│                     │  AdminService    │                        │
│                     ├──────────────────┤                        │
│                     │ • initialize()   │                        │
│                     │ • login()        │                        │
│                     │ • logout()       │                        │
│                     │ • getAllUsers()  │                        │
│                     │ • deleteUser()   │                        │
│                     │ • getUserDetails│                        │
│                     └──────────────────┘                        │
│                            │    │                               │
│              ┌─────────────┘    └─────────────┐                 │
│              ▼                                 ▼                 │
│    ┌──────────────────┐              ┌──────────────────┐       │
│    │ SecureAuthService│              │ StorageService   │       │
│    ├──────────────────┤              ├──────────────────┤       │
│    │ • loadRecord()   │              │ • save()         │       │
│    │ • saveRecord()   │              │ • load()         │       │
│    │ • deleteRecord() │              │ • remove()       │       │
│    └──────────────────┘              └──────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        DATA STORAGE                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │  iOS Keychain   │              │  UserDefaults   │          │
│  ├─────────────────┤              ├─────────────────┤          │
│  │                 │              │                 │          │
│  │ Admin Account:  │              │ Sessions        │          │
│  │  • Email        │              │ Truth Checks    │          │
│  │  • Password Hash│              │ Settings        │          │
│  │  • Salt         │              │ Admin Session   │          │
│  │  • Created At   │              │                 │          │
│  │                 │              │ User Accounts:  │          │
│  │ User Accounts:  │              │  • Sessions[]   │          │
│  │  • Email        │              │  • TruthChecks[]│          │
│  │  • Password Hash│              │  • Profile      │          │
│  │  • Name         │              │  • Settings     │          │
│  │  • Profile      │              │                 │          │
│  │                 │              │                 │          │
│  └─────────────────┘              └─────────────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow Diagrams

### 1. Admin Initialization Flow

```
┌──────┐
│ User │
└──┬───┘
   │ Taps "Initialize Admin"
   ▼
┌────────────────┐
│ AdminSetupView │
└───────┬────────┘
        │ initializeAdmin(email, password)
        ▼
┌──────────────┐
│AdminService  │
└──────┬───────┘
       │ 1. Check if admin exists
       │ 2. Generate salt
       │ 3. Hash password
       │ 4. Create AdminAccount
       ▼
┌──────────────┐
│   Keychain   │ ← Save admin credentials
└──────────────┘
```

### 2. Admin Login Flow

```
┌──────┐
│ User │ Enters email & password
└──┬───┘
   ▼
┌─────────────────┐
│ AdminLoginView  │
└────────┬────────┘
         │ loginAdmin(email, password)
         ▼
┌──────────────────┐
│  AdminService    │
└────────┬─────────┘
         │ 1. Load admin from keychain
         │ 2. Hash entered password
         │ 3. Compare hashes (constant-time)
         │ 4. If match, create session
         ▼
┌──────────────────┐
│  UserDefaults    │ ← Save session flag
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ AdminDashboard   │ ← Navigate to dashboard
└──────────────────┘
```

### 3. User Management Flow

```
┌──────┐
│ User │ Taps "View Users"
└──┬───┘
   ▼
┌────────────────────┐
│ AdminDashboardView │
└──────────┬─────────┘
           │ getAllUsers()
           ▼
┌──────────────────┐
│  AdminService    │
└──────┬───────────┘
       │ 1. Check authentication
       │ 2. Load user records
       │ 3. Load sessions
       │ 4. Load truth checks
       │ 5. Aggregate data
       ▼
┌──────────────────┐
│ SecureAuthService│
│ + StorageService │
└──────┬───────────┘
       │ Read from:
       │ • Keychain (credentials)
       │ • UserDefaults (sessions/data)
       ▼
┌──────────────────┐
│ [UserAccountInfo]│ ← Return user list
└──────────────────┘
```

### 4. User Deletion Flow

```
┌──────┐
│ User │ Confirms delete
└──┬───┘
   ▼
┌────────────────────┐
│ AdminDashboardView │
└──────────┬─────────┘
           │ deleteUser(email)
           ▼
┌──────────────────┐
│  AdminService    │
└──────┬───────────┘
       │ 1. Check authentication
       │ 2. Find user
       │ 3. Delete all data
       ▼
┌─────────────────────────────┐
│ Delete from:                │
│ • Keychain (credentials)    │
│ • UserDefaults (sessions)   │
│ • UserDefaults (truthChecks)│
│ • UserDefaults (settings)   │
│ • UserDefaults (profile)    │
└─────────────────────────────┘
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      SECURITY LAYERS                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Layer 1: Authentication                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Email/Password login                                  │   │
│  │ • Session token stored in UserDefaults                  │   │
│  │ • Logout clears session                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Layer 2: Password Security                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • SHA-256 hashing                                       │   │
│  │ • 120,000 iterations (PBKDF2-like)                      │   │
│  │ • Random salt per account                               │   │
│  │ • Constant-time comparison                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Layer 3: Storage Security                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • iOS Keychain for sensitive data                       │   │
│  │ • AccessibleAfterFirstUnlockThisDeviceOnly              │   │
│  │ • No plaintext passwords                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Layer 4: Authorization                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Every admin operation checks authentication           │   │
│  │ • Throws NotAuthorized if session invalid               │   │
│  │ • Separate admin/user sessions                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Component Relationships

```
AdminAccessView
    ├─ Checks: AdminService.adminExists()
    ├─ If false → Shows: AdminSetupView
    └─ If true → Shows: AdminLoginView
                            │
                            ├─ Calls: AdminService.loginAdmin()
                            └─ On success → Shows: AdminDashboardView
                                                        │
                                                        ├─ Loads: AdminService.getAllUsers()
                                                        ├─ Shows: User list
                                                        └─ On tap → Shows: UserDetailsView
                                                                            │
                                                                            └─ Loads: AdminService.getUserDetails()
```

## Data Models

```
AdminAccount
├─ email: String
├─ passwordHash: String
├─ passwordSalt: String
├─ createdAt: String
└─ lastLoginAt: String?

UserAccountInfo
├─ email: String (id)
├─ name: String
├─ createdAt: String
├─ onboardingProfile: OnboardingProfile?
├─ sessionCount: Int
├─ totalMinutes: Int
├─ lastSessionDate: String?
└─ truthCheckCount: Int
```

## State Management

```
Admin Authentication State:
┌────────────────────┐
│ Not Initialized    │ ──initialize()──▶ ┌─────────────┐
└────────────────────┘                    │ Initialized │
                                          └──────┬──────┘
                                                 │
                                            login()
                                                 │
                                                 ▼
                        logout()          ┌─────────────┐
                      ◀───────────────────│ Logged In   │
                                          └─────────────┘
```

## File Dependencies

```
AdminDashboardView.swift
    ├─ imports: SwiftUI
    ├─ depends on: AdminService
    ├─ depends on: AdminModels
    ├─ depends on: MivoColors
    └─ uses: AppViewModel (EnvironmentObject)

AdminService.swift
    ├─ imports: Foundation, CryptoKit, Security
    ├─ depends on: AdminModels
    ├─ depends on: SecureAuthService (user data)
    ├─ depends on: StorageService
    └─ provides: Admin operations API

AdminModels.swift
    ├─ imports: Foundation
    ├─ provides: AdminAccount
    ├─ provides: UserAccountInfo
    └─ provides: AdminError

MivoColorsExtension.swift
    ├─ imports: SwiftUI
    ├─ extends: MivoColors
    └─ provides: success, warning, error colors
```

## Integration Points

```
Your Existing App
    │
    ├─ SettingsView
    │     └─ Add: AdminAccessView entry point
    │
    ├─ AppViewModel
    │     └─ Used by: AdminDashboardView
    │
    ├─ SecureAuthService
    │     └─ Used by: AdminService (for user data)
    │
    ├─ StorageService
    │     └─ Used by: AdminService (for sessions/data)
    │
    └─ MivoColors
          └─ Extended by: MivoColorsExtension
```

## Usage Flow Example

```
1. User opens app
2. Goes to Settings
3. Taps "Admin Access" (or hidden gesture)
   │
   ├─ First Time:
   │     ├─ Shows AdminSetupView
   │     ├─ User taps "Create Admin Account"
   │     ├─ AdminService.initializeAdmin()
   │     └─ Credentials saved to Keychain
   │
   └─ Subsequent Times:
         ├─ Shows AdminLoginView
         ├─ User enters credentials
         ├─ AdminService.loginAdmin()
         ├─ Session created
         ├─ Shows AdminDashboardView
         │     ├─ Loads all users
         │     ├─ Displays statistics
         │     └─ User can:
         │           ├─ Search users
         │           ├─ View details
         │           ├─ Delete users
         │           └─ Refresh data
         │
         └─ On logout:
               ├─ AdminService.logoutAdmin()
               └─ Returns to login screen
```

---

This architecture provides:
- ✅ Clear separation of concerns
- ✅ Secure credential storage
- ✅ Session management
- ✅ User data isolation
- ✅ Easy testing
- ✅ Maintainable code structure
