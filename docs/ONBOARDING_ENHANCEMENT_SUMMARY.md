# Enhanced Onboarding Flow - Summary

## Overview
The onboarding experience has been completely redesigned to go deeper into understanding each user's unique relationship with their phone. Instead of a quick 3-step process, we now have a comprehensive 6-step journey that builds genuine self-awareness and commitment.

## New Onboarding Flow

### Step 1: Welcome (Existing - Updated)
**File:** `OnboardingWelcomeView.swift`
- **What changed:** Now flows i nto the new PhoneRelationshipView instead of WhyView
- **Purpose:** Set the tone and introduce Mivo's philosophy

---

### Step 2: Phone Relationship (NEW) 🆕
**File:** `OnboardingPhoneRelationshipView.swift`
- **Eyebrow:** "Self-awareness"
- **Question:** "How does your phone make you feel?"
- **Purpose:** Help users identify their emotional relationship with their device

**What users select:**
- 😰 Anxious - "I feel tense or worried when using my phone"
- 😨 FOMO - "I'm afraid I'll miss something important"
- 😶 Numbed - "I scroll to avoid feeling or thinking"
- 🤯 Overwhelmed - "Too much information, too fast"
- 🤪 Distracted - "I can't focus on one thing"
- 😔 Guilty - "I know I should stop, but I don't"
- 😬 Restless - "I reach for my phone when I'm idle"
- 🔁 Compulsive - "It feels automatic, not intentional"

**Key features:**
- Multi-select cards with emojis
- Dynamic feedback based on selections
- "Why this matters" insight box explaining the value
- Data saved to AI dataset for personalization

---

### Step 3: Triggers (NEW) 🆕
**File:** `OnboardingTriggersView.swift`
- **Eyebrow:** "Awareness"
- **Question:** "When do you reach for your phone?"
- **Purpose:** Map out the specific moments/contexts when phone use becomes automatic

**What users identify:**
- 🌅 First thing in the morning - "Before I even get out of bed"
- ⏳ While waiting - "In line, waiting for someone, etc."
- 💤 When I'm bored - "To fill empty moments"
- ⚠️ When I'm anxious - "To distract from stress"
- 🍽️ During meals - "Can't eat without scrolling"
- 💧 In the bathroom - "Every single time"
- 🛏️ Right before bed - "The last thing I do at night"
- 🔄 Between activities - "Moving between tasks or locations"
- 🔔 After a notification - "Instantly, without thinking"
- 👥 In social settings - "Even when I'm with people"

**Key features:**
- Icon-based trigger cards
- "Pattern Recognition" explanation card
- Builds awareness of automatic behaviors
- Saved for later insights and interventions

---

### Step 4: Goals (NEW) 🆕
**File:** `OnboardingGoalsView.swift`
- **Eyebrow:** "Your vision"
- **Question:** "What would you like to reclaim?"
- **Purpose:** Shift focus from "phone bad" to "life good" - what they're gaining, not losing

**What users can select:**
- ☀️ Calm mornings - "Start my day with intention instead of scrolling"
- 🎯 Deep work - "Focus on meaningful work without constant interruptions"
- ❤️ Quality time - "Be fully present with the people I care about"
- 📚 More reading - "Reclaim time for books, articles, and longer-form content"
- 😴 Better sleep - "Put the phone down and actually rest"
- 🌿 Be present - "Notice the world around me instead of living through a screen"
- 🎨 Create more - "Use my hands and mind to make things, not just consume"

**Key features:**
- Each goal shows time impact ("15-30 min saved", "Priceless", etc.)
- Custom goal text field for personal visions
- Emphasizes what users are *gaining* not restricting
- Creates positive motivation

---

### Step 5: Commitment (NEW) 🆕
**File:** `OnboardingCommitmentView.swift`
- **Eyebrow:** "Your commitment"
- **Question:** "How do you want to approach this?"
- **Purpose:** Set realistic expectations and choose an approach that matches their readiness

**Commitment levels:**

#### 🌱 Gentle Start
- **Subtitle:** "Small steps, sustainable pace"
- **Description:** Build awareness first without pressure
- **Features:**
  - Pattern tracking and insights
  - Optional pauses before opening apps
  - Weekly reflections

#### ⚖️ Steady Progress
- **Subtitle:** "Balanced and intentional"
- **Description:** Real changes while staying flexible
- **Features:**
  - All Gentle features
  - Daily intention prompts
  - Truth check reminders
  - Usage goal suggestions

#### 🎯 Focused Change
- **Subtitle:** "Clear boundaries, faster results"
- **Description:** Serious commitment with accountability
- **Features:**
  - All Moderate features
  - Mandatory pause before selected apps
  - Time limits and alerts
  - Accountability check-ins

**Key features:**
- Personal pledge writing (optional but powerful)
- Sheet modal for composing pledge
- Assurance they can change commitment level later
- Saved to personalize friction levels in the app

---

### Step 6: Apps (Existing - Updated)
**File:** `OnboardingAppsView.swift`
- **What changed:** Updated from step "3 of 3" to "6 of 6"
- **Purpose:** Select which apps to track and add friction to

---

## Benefits of the New Flow

### 1. **Deeper Self-Awareness**
- Users reflect on feelings, triggers, and goals before making changes
- Creates genuine "aha moments" about their phone use patterns
- Builds intrinsic motivation instead of external pressure

### 2. **Personalization**
- Each user's data creates a unique profile
- Mivo can reference their goals when suggesting pauses
- Insights can be tailored to their specific triggers and feelings

### 3. **Commitment**
- Writing a personal pledge increases follow-through
- Choosing a commitment level sets appropriate friction
- Users feel ownership over their journey

### 4. **Better Retention**
- More invested users = higher engagement
- Understanding "why" before "how" prevents early churn
- Users feel seen and understood by the app

### 5. **Richer AI Dataset**
All collected data flows into the AI dataset for:
- Personalized intervention timing
- Custom insight generation
- Pattern recognition specific to their triggers
- Goal-oriented progress tracking

---

## New Data Models

### PhoneFeeling (Enum)
```swift
case anxious, fomo, numbed, overwhelmed, distracted, guilty, restless, compulsive
```

### PhoneTrigger (Enum)
```swift
case wakeUp, waiting, bored, anxious, eating, bathroom, bedtime, 
     transition, notification, social
```

### PhoneGoal (Enum)
```swift
case morningRoutine, deepWork, quality_time, reading, sleep, 
     presence, creativity
```

### CommitmentLevel (Enum)
```swift
case gentle, moderate, focused
```

---

## Technical Implementation

### Data Flow
1. Each screen collects specific user selections
2. Data is formatted into text summaries
3. Saved via `appVM.appendAISummary()` to the AI dataset
4. Stored in UserDefaults under the `aiDataset` key
5. Available for AI personalization and insights

### UI/UX Patterns
- **OnboardingEntrance animations** - Staggered fade-in for each element
- **Multi-select cards** - Visual feedback with checkmarks and color changes
- **Dynamic summaries** - Real-time feedback on selections
- **Insight boxes** - Educational content explaining "why"
- **Progress indicators** - "Step X of 6" in headers
- **Blue accent for CTAs** - New blue color (#4A6FA5) for primary actions

### Accessibility
- All selectable items use standard iOS patterns
- High contrast text and backgrounds
- Descriptive labels on all interactive elements
- Supports Dynamic Type

---

## Future Enhancements

### Potential Additions:
1. **Screen Time Permission** - Prompt for iOS Screen Time API access
2. **Notification Preferences** - When they want reminders
3. **Accountability Partner** - Option to share progress with someone
4. **Baseline Calibration** - Actual Screen Time data to set realistic goals
5. **Quick Start Option** - Skip button for users who want minimal onboarding

### Analytics to Track:
- Completion rate by step
- Drop-off points
- Most selected feelings/triggers/goals
- Correlation between commitment level and long-term retention
- Time spent in onboarding vs. time spent in app later

---

## Files Created

✅ `OnboardingPhoneRelationshipView.swift` - Step 2: Emotional awareness
✅ `OnboardingTriggersView.swift` - Step 3: Behavioral triggers  
✅ `OnboardingGoalsView.swift` - Step 4: Vision and goals
✅ `OnboardingCommitmentView.swift` - Step 5: Personal commitment

## Files Modified

📝 `OnboardingWelcomeView.swift` - Updated navigation to new flow
📝 `OnboardingAppsView.swift` - Updated step counter (6 of 6)

---

## Color Palette Used

The new screens use your updated 2026 palette:
- **Background:** #FAF3E8 (warm, light)
- **Surface:** #F0E4CC (cards)
- **Accent:** #D4872A (amber highlights)
- **Blue:** #4A6FA5 (CTAs and interactive elements) 🆕
- **Primary text:** #5C3317 (headings)
- **Secondary text:** #B5621E (labels)

This creates a cohesive, modern, trustworthy experience.

---

## How to Test

1. Clear onboarding state in Settings
2. Log out (if logged in)
3. Start fresh - you'll see the welcome screen
4. Flow through all 6 steps
5. Check that data appears in the AI dataset
6. Verify that selections persist across app restarts

---

🎉 **The onboarding is now significantly more thoughtful, personalized, and engaging!**
