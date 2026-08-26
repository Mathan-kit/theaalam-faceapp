# Face Attendance Admin Portal - Design System

## Brand & Style
The brand personality is rooted in reliability, security, and effortless efficiency. Designed for enterprise environments where "Face Attendance" must feel both high-tech and incredibly approachable, the style follows a **Corporate / Modern** aesthetic with leanings toward **Minimalism**. 

The UI is intentionally quiet to allow the utility of the biometric scanning to remain the focus. By utilizing heavy whitespace and a restricted color palette, the system evokes a sense of "enterprise-grade" stability. The emotional response is one of professional trust; it is a tool that works instantly and securely without unnecessary visual noise.

## 🎨 Color Palette

The palette is dominated by **Deep Blue (#1A56DB)**, serving as the primary anchor for actions, progress indicators, and brand presence. 

### Core Colors
- **Primary:** `#003fb1`
- **Primary Container:** `#1a56db` (Deep Blue)
- **On Primary Container:** `#d4dcff`
- **Secondary:** `#7127e5`
- **Secondary Container:** `#8b4aff`
- **Tertiary:** `#852b00`

### Surface & Background
- **Background / Surface:** `#f8f9fb` (Light Gray / White)
- **Surface Container Lowest:** `#ffffff`
- **Surface Container Low:** `#f3f4f6`
- **On Surface:** `#191c1e`
- **Outline:** `#737686`

### Semantic Colors
- **Error:** `#ba1a1a`
- **Error Container:** `#ffdad6`
- **On Error Container:** `#93000a`
Success Green and Error Red are reserved strictly for feedback (e.g., "Scan Successful" or "Face Not Recognized").

## 🔤 Typography

**Inter** is the sole typeface for this design system, chosen for its exceptional legibility on mobile screens and its systematic, neutral character. Hierarchy is established through weight and scale.

- **Headline Large (Desktop):** 28px, Bold (700), Line Height 34px, Letter Spacing -0.02em
- **Headline Large (Mobile):** 24px, Bold (700), Line Height 30px
- **Headline Medium:** 20px, Semi-Bold (600), Line Height 28px, Letter Spacing -0.01em
- **Body Large:** 16px, Regular (400), Line Height 24px
- **Body Medium:** 14px, Regular (400), Line Height 20px
- **Label Medium:** 12px, Semi-Bold (600), Line Height 16px, Letter Spacing 0.05em (Uppercase)

## 📏 Layout & Spacing

The layout follows a **Fluid Grid** model optimized for mobile portrait orientation.
- **Container Padding (Horizontal Margin):** 24px (1.5rem)
- **Stack Gap:** 16px (1rem)
- **Inline Gap:** 12px (0.75rem)
- **Section Margin:** 32px (2rem)
- **Vertical Rhythm:** Maintained using a 4px baseline.

## 🔷 Shapes & Elevation

This design system utilizes **Ambient Shadows** to create a subtle sense of depth without looking dated.
- **Elevation:** Shadows are applied sparingly to "Floating" elements. Shadow Style uses a very soft, 12% opacity Deep Blue tint with a 15px to 20px blur radius. Secondary information uses Light Gray (#F3F4F6) fill without shadows.
- **Shapes (Rounded Level 2):**
  - **Small:** 4px (0.25rem)
  - **Default:** 8px (0.5rem)
  - **Medium:** 12px (0.75rem)
  - **Large (Primary Cards):** 16px (1rem)
  - **Extra Large (Scanning Viewport):** 24px (1.5rem) or perfect circle.

## 🧩 Components (Across Screens)

### Screens Analyzed
1. **Admin Login**
2. **Home - Face Recognition**
3. **Register Employee Face**

### Component Styles
- **Buttons:**
  - **Primary Buttons:** Deep Blue background (`#1a56db`) with white text and a subtle shadow. 12px border radius.
  - **Secondary/Ghost Buttons:** 1px border in Light Gray with no background.
- **Input Fields:**
  - Light Gray background with a 1px inset border. 12px border radius.
  - **Focus State:** Border transitions to Primary Blue (`#003fb1`).
  - **Labels:** Floating labels used to maintain context in a compact mobile view.
- **Attendance Cards:**
  - Used for logs or user status.
  - Left-aligned colored border (Green for Present, Gray for Absent) to provide quick visual scanning at a glance. 16px border radius.
- **Icons:**
  - **Navigation/Inputs:** 2px stroke-weight outline icons (e.g., Home, Settings, Search).
  - **Primary Actions:** Filled versions of the same icon set for high emphasis (e.g., the "Check-In" camera icon).
- **The Scanner Overlay (Face Recognition/Registration):**
  - Semi-transparent dark overlay (60%) with a clear cut-out for the face.
  - Subtle animated "corner brackets" in Primary Blue guide the user's facial alignment.
